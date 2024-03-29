#!/usr/bin/perl -w
use Data::Dumper;
use Switch;

my $me = `whoami`;
chomp $me;
if ($me !~ /root/){
    die("need to execute as root user. exiting.\n");
}

#figure out which type of OS we have.
my $os = 0;
my $osval = `cat /etc/redhat-release|grep release`;
chomp $osval;
if ($osval =~ /release 5/){$os = 5;}
elsif ($osval =~ /release 6/){$os = 6;}
else {die "uncaught os type\n";}

my @disks = `mount|egrep 'ext3|xfs|ext4'`;
my @phys = ();
my @type = ();

foreach my $d (@disks) {
    my @s = split / /,$d;
    #print Dumper(@s);
    push(@phys,$s[0]);
    push(@type,$s[4]);
}

my $i = 0;
my $totaltime = 0;
my $xfs_seen = 0;
my $ext3_seen = 0;
my $ext4_seen = 0;
my $check_note = 0;
my $count_note = 0;

foreach my $d (@phys){

    my $dtype 				= $type[$i];
    my $mount_count 	 	= 0;
    my $mount_max 		 	= 0;
    my $last_check 			= "";
    my $check_interval	 	= 0;
    my $check_interval_test = 0;
    my $check_next		 	= "";

    my $mount_countcheck	= 0;
    my $old_check_date	 	= 0;
    my $disk_size		 	= 0;

    my $ext3				= 36;   #seconds per 1 gb
    my $ext4				= 6;	#seconds per 1 gb
    my $xfs					= 6;	#seconds per 1 gb

    my $tunetype			= "";

    if ($os == 6){$tunetype = "tune2fs";}
    if ($os == 5){
        if($dtype =~ /ext3/) {$tunetype = "/sbin/tune2fs";}
        if($dtype =~ /ext4/) {$tunetype = "/sbin/tune4fs";}
    }

    my @o = `$tunetype -l $d|egrep 'Last checked|Check interval|Mount count|Maximum mount count|Next check after'`;
    #print Dumper(\@o);

    foreach my $x (@o) {
        chomp $x;
        #print Dumper($x);
        my @v = split /: +/, $x;
        #print Dumper(\@v);

        switch ($v[0]) {
            case /Last checked/		{$last_check 		= $v[1];}
            case /Check interval/	{$check_interval	= $v[1];}
            case /Next check after/ {$check_next		= $v[1];}
            case /Mount count/		{$mount_count		= $v[1];}
            case /Maximum mount/	{$mount_max		= $v[1];}
            else {die("encountered something else\n");}
        }

        if($check_interval =~ /none/){
            $check_interval_test = 1;
        }

        #handle mount counts
        if ($mount_max == -1) {
            $mount_countcheck = 1;
            $count_note = 1;
        }else{
            if($mount_count > $mount_max){
                $mount_countcheck = 1;
            }else{
                $mount_countcheck = 0;
            }
        }

        #check if next scheduled check is in the future.
        if ($check_next =~ /./){
            my $check_next_epoch = `date -d \"$check_next\" +%s`;
            my $now_epoch = `date +%s`;
            chomp $check_next_epoch;
            chomp $now_epoch;
            if($now_epoch > $check_next_epoch){
                $old_check_date = 1;
            }else {
                $old_check_date = 0;
            }
        }
    }

    ### Get disk sizes
    my $size = `/bin/df -P $d|grep $d`;
    chomp $size;
    my @sp = split / +/, $size;

    $disk_size = $sp[1];
    $disk_size /= 1024;
    $disk_size /= 1024;

    my $fscktime = 0;
    if   ($dtype =~ /ext3/){$fscktime = $disk_size*$ext3; $ext3_seen = 1;}
    elsif($dtype =~ /ext4/){$fscktime = $disk_size*$ext4; $ext4_seen = 1;}
    elsif($dtype =~ /xfs/){$fscktime = $disk_size*$xfs; $xfs_seen = 1;}
    else {die "enountered unknown type: >$dtype<\n";}

    $fscktime /= 60;

    ### Print output
    my $msg = "$d ($dtype, ".int($disk_size)." GB):\n";
    if($check_interval_test){
        $msg .= "Failed last check: $last_check / no check interval\n";
        $check_note = 1;
    }elsif($old_check_date == 1){
        $msg .= "Failed next check: $check_next is in the past\n";
    }
    
    if($mount_countcheck == 1){
        $msg .= "Failed mount count: $mount_count/$mount_max too high\n";
    }
    if($mount_countcheck || $old_check_date || $check_interval_test){
        $msg .= "Time to fsck: ".int($fscktime)." min\n";
        $totaltime += $fscktime;
    }
    else {  $msg .= "Passed. Disk $check_next > now, mount count: $mount_count/$mount_max\n"; }

    print $msg."\n";
    $msg = "";
    $i++;
    #exit 1;
}

print "Total fsck time for server: ".int($totaltime)." minutes\n\n";

my $hmsg = "";
if($count_note == 1){
	$hmsg .= "Max check count isn't set. \n";
	$hmsg .= "\text3: Set with tune2fs -c 31 /dev/disk/drive\n";
	if($os == 5 && $ext4_seen) { $hmsg .= "\text4: Set with tune4fs -c 31 /dev/disk/drive\n"; }
}
if($check_note == 1){
	$hmsg .= "Max time between checks isn't set.\n";
	$hmsg .= "\text3: Set with tune2fs -i 6m /dev/disk/drive\n";
	if($os == 5 && $ext4_seen) { $hmsg .= "\text4: Set with tune4fs -i 6m /dev/disk/drive\n"; }
}

print $hmsg;

#!/usr/bin/env perl

use 5.010;
use warnings;
use strict;

use Data::Dumper;

my $map = sub {
    my( $path, $size ) = @_;
    my( %m, @m )= ();

    my $dfh = `df -h $path`;
    die "mountpoint $path doesnt exist" unless $dfh =~ /.*/;

    open(my $fh,'<', \$dfh);
    while(<$fh>){
        chomp; next if $_ =~ /Filesystem/;
        ( $m{lv_path}, $m{size}, $m{used}, $m{avail}, $m{used_perc}, $m{mountpoint})  = split(/\s+/, $_);
        ( $m{vg}, $m{lv} ) = split(" ", `lvs $m{lv_path} --noheadings -o vg_name,lv_name`);

        my @pv = ();
        open my $p,'-|',"pvs -a";
        while( <$p> ){
            if(/(\/.*?) .*?($m{vg})/){ 
                chomp $1; push @pv, $1;
            }
        }

        $m{pv} = \@pv; close $p;
        $m{disk} = $m{pv}->[0]; $m{disk} =~ s/[0-9]+//g;

        open $p,'-|',"lsblk -dnl $m{disk} --output SIZE";
        chomp( $m{disk_size} = <$p> ); close $p;

        open $p,'-|',"lsblk -dnl $m{lv_path} --output SIZE";
        chomp( $m{lv_size} = <$p> ); close $p;

        $m{pv_next} = $m{disk} . ($#pv + 2);
        $m{pv_last} = $#pv + 1;

        $m{fdisk_seq} = ["n\n","\n","\n","\n","\n","t\n","\n","8e\n","\n","w\n"]; 
        $m{fdisk_seq}->[3] = "$size\n" if defined $size;
    }
    return \%m;
};

my $create_part = sub {
	my $m = shift;
    open my $psss,'>&',STDOUT;
    open STDOUT,'+>', undef;
	open my $p,'|-', "fdisk $m->{disk}" ;
    for( @{$m->{fdisk_seq}} ){ print $p $_ };
	close $p;
    open STDOUT,'>&',$psss;
	system("partprobe $m->{disk}");
    say "pvcreate";
	system("pvcreate $m->{pv_next}");
	system("vgextend $m->{vg} $m->{pv_next}");

};

my $lv_extend = sub {
    my $m = shift;
    system("lvextend -l +100%FREE /dev/$m->{vg}/$m->{lv}");
	system("resize2fs /dev/$m->{vg}/$m->{lv}");
};

my $lvm = sub {
    my( $path, $size ) = @_;
    my $dfh = `df -h $path`; chomp $dfh;
    die if $dfh !~ /$path/;

    my $m = $map->($path, $size);
    say Dumper $m if $ENV{lvextender} == 1;
    die "cant create more LVM partitions on $m->{disk}" if $m->{pv_last} == 4;
    if( $m->{disk_size} eq $m->{lv_size} ){ say Dumper $m and die "$m->{lv} size same as $m->{disk} size, nothing to do" }
    else { $create_part->($m,$size); sleep 1; say $lv_extend->($m) }
};

$lvm->(@ARGV);







__DATA__

in VMWare add new disk 5G
reboot linux
lsblk will show new disk with NAME sdc (if sda and sdb exist.. every new disk uses next letter in alphabet as last letter )

create partition sdc1 for full current space 5G (fdisk /dev/sdc)
initialize pv to use with lvm (pvcreate /dev/sdc1)
create vg and add /dev/sdc1 partition (vgcreate vg_repodata /dev/sdc1;
create lv on sdc1 full extend to disk size(5G) and add it in vg  (lvcreate -n lv_big -l 100%FREE vg_repodata)
make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)
mount lv to mountpoint (mount /dev/vg_repodata/lv_big /big)
put in /etc/fstab (/dev/vg_repodata/lv_big /big ext4 defaults 0 1)

OTHER COMMANDS
remove PV
- first remove PV frmom VG (vgreduce vg_repodata /dev/sdb3)
- then remove PV from LVM (pvremove /dev/sdb3)

if doesnt work

- remove partition fdisk /dev/sdb
- remove PV (vgreduce --removemissing --force vg_repodata)

----
extend disk in vm to 7G

sdc                      8:16   0    7G  0 disk
└─sdc1                   8:17   0    5G  0 part
  └─vg_repodata-lv_big 252:0    0    5G  0 lvm
----

create partition sdc2 for remainging space 2G
initialize pv to use with lvm (pvcreate /dev/sdc2)
force kernel to use new part table (partprobe /dev/sdc)
Add this pv to vg_tecmint vg to extend the size of a volume group to get more space for expanding lv(vgextend vg_tecmint /dev/sda2)
check available Physical Extends( available Physical Extend )
expand lv(lvextend -l +4607 /dev/vg_repodata/lv_big)
resize fs (resize2fs /dev/vg_repodata/lv_big)

create lv vg on sdc2 full extend (2G)
???check fstype(df -T /big)
???make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)

# http://unix.stackexchange.com/questions/199164/error-run-lvm-lvmetad-socket-connect-failed-no-such-file-or-directory-but
#system("systemctl enable lvm2-lvmetad.service && systemctl enable lvm2-lvmetad.socket && systemctl start lvm2-lvmetad.service && systemctl start lvm2-lvmetad.socket");

package FusionInventory::Agent::Task::Inventory::OS::AIX::Storages;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::AIX;

sub isEnabled {
    return
        can_run('lsdev') &&
        can_run('lsattr');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{inventory};

    # index VPD infos by AX field
    my $infos = _getIndexedInfos(logger => $logger);

    foreach my $disk (_getDisks(logger => $logger, subclass => 'scsi', infos => $infos)) {
        $disk->{DISKSIZE} = _getCapacity($disk->{NAME}, $params{logger});
        $disk->{SERIAL}   = getFirstMatch(
            command => "lscfg -p -v -s -l $disk->{NAME}",
            logger  => $params{logger},
            pattern => qr/Serial Number\.*(.*)/
        );
        $inventory->addEntry(section => 'STORAGES', entry => $disk);
    }

    foreach my $disk (_getDisks(logger => $logger, subclass => 'fcp', infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $disk);
    }

    foreach my $disk (_getDisks(logger => $logger, subclass => 'fdar', infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $disk);
    }

    foreach my $disk (_getDisks(logger => $logger, subclass => 'sas', infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $disk);
    }

    foreach my $disk (_getDisks(logger => $logger, subclass => 'vscsi', infos => $infos)) {
        $disk->{DISKSIZE}     = _getVirtualCapacity($disk->{NAME}, $params{logger});
        $disk->{MANUFACTURER} = "VIO Disk";
        $disk->{MODEL}        = "Virtual Disk";
        $inventory->addEntry(section => 'STORAGES', entry => $disk);
    }

    foreach my $cdrom (_getCDROMs(logger => $logger, infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $cdrom);
    }

    foreach my $tape (_getTapes(logger => $logger, infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $tape);
    }

    foreach my $floppy (_getFloppies(logger => $logger, infos => $infos)) {
        $inventory->addEntry(section => 'STORAGES', entry => $floppy);
    }
}

sub _getIndexedLsvpdInfos {
    my %infos = 
        map  { $_->{AX} => $_ }
        grep { $_->{AX} }
        getLsvpdInfos(@_);

    return \%infos;
}

sub _getDisks {
    my (%params) = @_;

    my $command = $params{subclass} ?
        "lsdev -Cc disk -s $params{subclass} -F 'name:description'" : undef;

    my @disks = _parseLsdev(
        command => $command,
        pattern => qr/^(.+):(.+)/,
        @_
    );

    foreach my $disk (@disks) {
        $disk->{TYPE} = 'disk';

        my $info = $params{infos}->{$disk->{NAME}};
        next unless $info;
        $disk->{MANUFACTURER} = _getManufacturer($info);
        $disk->{MODEL}        = _getModel($info);
    }

    return @disks;
}

sub _getCdroms {
    my (%params) = @_;

    my @cdroms = _parseLsdev(
        command => "lsdev -Cc cdrom -s scsi -F 'name:description:status'",
        pattern => qr/^(.+):(.+):.+Available.+/,
        @_
    );

    foreach my $cdrom (@cdroms) {
        $cdrom->{TYPE} = 'cd';
        $cdrom->{DISKSIZE} = _getCapacity($cdrom->{NAME}, $params{logger});

        my $info = $params{infos}->{$cdrom->{NAME}};
        next unless $info;
        $cdrom->{MANUFACTURER} = _getManufacturer($info);
        $cdrom->{MODEL}        = _getModel($info);
    }

    return @cdroms;
}

sub _getTapes {
    my (%params) = @_;

    my @tapes = _parseLsdev(
        command => "lsdev -Cc tape -s scsi -F 'name:description:status'",
        pattern => qr/^(.+):(.+):.+Available.+/,
        @_
    );

    foreach my $tape (@tapes) {
        $tape->{TYPE} = 'tape';
        $tape->{DISKSIZE} = _getCapacity($tape->{NAME}, $params{logger});

        my $info = $params{infos}->{$tape->{NAME}};
        next unless $info;
        $tape->{MANUFACTURER} = _getManufacturer($info);
        $tape->{MODEL}        = _getModel($info);
    }

    return @tapes;
}

sub _getFloppies {
    my (%params) = @_;

    my @floppies = _parseLsdev(
        command => "lsdev -Cc diskette -F 'name:description:status'",
        pattern => qr/^(.+):(.+):.+Available.+/,
        @_
    );

    foreach my $floppy (@floppies) {
        $floppy->{TYPE} = 'floppy';
    }

    return @floppies;
}

sub _parseLsdev {
    my (%params) = @_;

    my $handle = getFileHandle(@_);
    return unless $handle;

    my @devices;

    while (my $line = <$handle>) {
        chomp $line;
        next unless $line =~ $params{pattern};

        push @devices, {
            NAME        => $1,
            DESCRIPTION => $2
        };
    }
    close $handle;

    return @devices;
}

sub _getCapacity {
    my ($device, $logger) = @_;

    return getLastLine(
        command => "lsattr -EOl $device -a 'size_in_mb'",
        logger  => $logger
    );
}

sub _getVirtualCapacity {
    my ($device, $logger) = @_;

    my ($model, $capacity);

    my @lines = getAllLines(
        command => "lspv $device",
        logger  => $logger
    );

    foreach my $line (@lines) {
        if ($line !~ /^0516-320.*/) {
            if ($line =~ /TOTAL PPs:/ ) {
                ($capacity, $model) = split(/\(/, $line);
                ($capacity, $model) = split(/ /, $model);
            }
        } else {
            $capacity = 0;
        }
    }

    return $capacity;
}

sub _getManufacturer {
    my ($device) = @_;

    return unless $device;

    return $device->{FN} ?
        "$device->{MF},FRU number :$device->{FN}" :
        "$device->{MF}"                           ;
}

sub _getModel {
    my ($device) = @_;

    return unless $device;

    return $device->{TM};
}

1;

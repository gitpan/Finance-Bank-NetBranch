use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Finance::Bank::NetBranch',
    AUTHOR              => 'Darren Kulp <darren@kulp.ch>',
    VERSION_FROM        => 'lib/Finance/Bank/NetBranch.pm',
    ABSTRACT_FROM       => 'lib/Finance/Bank/NetBranch.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Alias'	=> 0,
        'HTML::Entities' => 0,
        'WWW::Mechanize' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Finance-Bank-NetBranch-*' },
);

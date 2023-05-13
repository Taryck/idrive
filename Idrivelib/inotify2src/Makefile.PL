use ExtUtils::MakeMaker;

my $mm = MM->new({
    dist         => {
       PREOP	=> 'pod2text Inotify2.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
       COMPRESS	=> 'gzip -9v',
       SUFFIX	=> '.gz',
	            },
    NAME         => "Linux::Inotify2",
    VERSION_FROM => "Inotify2.pm",
    PREREQ_PM    => {
       common::sense => 0,
    },
});

$mm->flush;


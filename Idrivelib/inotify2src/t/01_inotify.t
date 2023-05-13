use Test::Simple tests => 5;
use Linux::Inotify2;

my $in = Linux::Inotify2->new;
ok ($in, "inotify handle created");

# create directory for watch
mkdir $$;

my $watch = $in->watch ($$, IN_ALL_EVENTS);
ok ($watch, "watch created for directory $$");

$in->blocking (0);

{
  my @list = $in->read;
  ok (@list==0, "non blocking: $!");
}

rmdir $$;

{
  my @list = $in->poll;
  ok (@list > 0, scalar @list . " events read");
}

ok ($watch->cancel, "watch canceled");

END {
  rmdir $$;
}


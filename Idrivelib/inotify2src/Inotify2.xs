#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <unistd.h>
#include <fcntl.h>

#include <sys/inotify.h>

MODULE = Linux::Inotify2                PACKAGE = Linux::Inotify2

PROTOTYPES: ENABLE

BOOT:
{
	HV *stash = GvSTASH (CvGV (cv));

        static const struct civ { const char *name; IV iv; } *civ, const_iv[] = {
          { "IN_ACCESS"       , IN_ACCESS        },
          { "IN_MODIFY"       , IN_MODIFY        },
          { "IN_ATTRIB"       , IN_ATTRIB        },
          { "IN_CLOSE_WRITE"  , IN_CLOSE_WRITE	 },
          { "IN_CLOSE_NOWRITE", IN_CLOSE_NOWRITE },
          { "IN_OPEN"         , IN_OPEN          },
          { "IN_MOVED_FROM"   , IN_MOVED_FROM    },
          { "IN_MOVED_TO"     , IN_MOVED_TO      },
          { "IN_CREATE"       , IN_CREATE        },
          { "IN_DELETE"       , IN_DELETE        },
          { "IN_DELETE_SELF"  , IN_DELETE_SELF   },
          { "IN_MOVE_SELF"    , IN_MOVE_SELF     },
          { "IN_UNMOUNT"      , IN_UNMOUNT       },
          { "IN_Q_OVERFLOW"   , IN_Q_OVERFLOW    },
          { "IN_IGNORED"      , IN_IGNORED       },
          { "IN_CLOSE"        , IN_CLOSE         },
          { "IN_MOVE"         , IN_MOVE          },
          { "IN_ONLYDIR"      , IN_ONLYDIR       },
          { "IN_DONT_FOLLOW"  , IN_DONT_FOLLOW   },
          { "IN_MASK_ADD"     , IN_MASK_ADD      },
          { "IN_ISDIR"        , IN_ISDIR         },
          { "IN_ONESHOT"      , IN_ONESHOT       },
          { "IN_ALL_EVENTS"   , IN_ALL_EVENTS    },
	};

        for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ > const_iv; civ--)
          newCONSTSUB (stash, (char *)civ[-1].name, newSViv (civ[-1].iv));
}

int
inotify_init ()

void
inotify_close (int fd)
	CODE:
        close (fd);

int
inotify_add_watch (int fd, char *name, U32 mask)

int
inotify_rm_watch (int fd, U32 wd)

int
inotify_blocking (int fd, I32 blocking)
	CODE:
        fcntl (fd, F_SETFL, blocking ? 0 : O_NONBLOCK);

void
inotify_read (int fd, int size = 8192)
	PPCODE:
{
	char buf [size], *cur, *end;
        int got = read (fd, buf, size);

        if (got < 0) {
          if (errno != EAGAIN && errno != EINTR) {
            croak ("Linux::Inotify2: read error while reading events");
          } else {
            XSRETURN_EMPTY;
		  }
		}

        cur = buf;
        end = buf + got;

        while (cur < end)
          {
            struct inotify_event *ev = (struct inotify_event *)cur;
            cur += sizeof (struct inotify_event) + ev->len;

            while (ev->len > 0 && !ev->name [ev->len - 1])
              --ev->len;
            
            HV *hv = newHV ();
            hv_store (hv, "wd",     sizeof ("wd")     - 1, newSViv (ev->wd), 0);
            hv_store (hv, "mask",   sizeof ("mask")   - 1, newSViv (ev->mask), 0);
            hv_store (hv, "cookie", sizeof ("cookie") - 1, newSViv (ev->cookie), 0);
            hv_store (hv, "name",   sizeof ("name")   - 1, newSVpvn (ev->name, ev->len), 0);

            XPUSHs (sv_2mortal (newRV_noinc ((SV *)hv)));
          }
}


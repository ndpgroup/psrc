Persisted SSH Remote Control (PSRC)
===================================

Run (bash) scripts across a set of hosts over persisted ssh control
sessions.

Installing
----------

Just download `psrc.sh`.

[psrc.sh](psrc.sh)

Configuring
-----------

Create a subdir called `commands.d` under the directory containing
`psrc.sh`.  And add whatever set of remote scripts you would like to
use.  For each remote script, defined a shell function with the same
name as the script.  For example:

```sh
#!/bin/bash

# File: commands.d/foo.sh

foo() {
  local arg="$1"
  shift
  case "$arg" in
    xyz)
      foo_xyz "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

foo_xyz() {
  blah blah
}
```

All commands should try to be "nice" regarding global function and
global variable scope, as all commands are run in the same shell
context.  This allows sharing of data between functions, but also can
lead to unintentional conflicts.  Use the bash `local` keyword for most
variables.

Running
-------

Once some commands have been defined, start a remote control session
from one host.  For the following examples, the remote hosts to be
controlled are called `slave1` .. `slave3`.  If the location where
`psrc.sh` and the commands directory is not shared among hosts, you can
first bootstrap the hosts to be controlled. Bootstrapping pushes the
control script and command files to the remote hosts (to a path under
`$TMPDIR` or `/tmp`, make sure `$TMPDIR` is set to somewhere that allows
execute):

```
./psrc.sh bootstrap slave1 slave2 slave3
```

Next, start a session for a set of hosts (more hosts can be added at any
time by repeating this command):

```
./psrc.sh connect slave1 slave2 slave3
```

Now run as many remote commands as desired over any / all of the remote
hosts.

```
./psrc.sh run slave1 foo xyz
./psrc.sh run ALL bar abc
./psrc.sh run slave3 baz 1 2 3
```

Note that the exit status from the remote script is returned and can be
tested for locally.  If the command was run on `ALL` hosts, then the
exit status will be `1` (fail) if any of the hosts returned non-zero
(failed).

When done with the session, close all the connections and cleanup:

```
./psrc.sh stop
```

Individual hosts can be added or removed at any time with:

```
./psrc.sh connect slaveX
./psrc.sh disconnect slaveX
```

The `ALL` operations always act on all currently connected hosts.

Also run `psrc.sh --help` for other usage.

Security
--------

THIS TOOL ALLOWS ARBITRARY REMOTE CODE EXECUTION TO ANYONE WITH WRITE
PERMISSION ON THE LOCAL (CONTROLLING HOST) CONTROL FIFO.

The FIFO is made with `mkfifo -m 0600` so this exploit should be limited
to the user who ran `connect` and anyone with root on the controlling
host.  But hey, this tool already assumes the running user can start a
full remote shell on the remote hosts, so who cares.

If all remote commands are issued via the `psrc.sh` script itself,
propper quoting / escaping is used to "do the right thing".  For
instance, running a remote command such as:

```
./psrc.sh run ALL foo '`date`'
```

will actually pass the literal string `` `date` `` to the `foo` command,
it will not be evaluated.

However, writing directly to the control socket, passing `` `date` ``
unescaped to the remote can cause the `date` command to actually be
evaluated on the remote.  Likewise passing other unescaped
metacharacters like `|&;()<>` can cause arbitrary remote code execution.

Customizing
-----------

The logic for psrc itself is contained entirely in the one script, so
just tweak away.  And feel free to rename the script to any name you
like, it should not care what it is named.

Dependencies
------------

On the local (controlling) host:

 * bash
 * find (only for bootstrap)
 * pkill (part of procps)
 * sed
 * shar (only for bootstrap)
 * ssh
 * GNU coreutils
   * basename
   * cat
   * cut
   * dirname
   * env
   * ls
   * mkdir
   * mkfifo
   * rm
   * rmdir
   * sort
   * test
   * tail

On the remote (controlled) hosts:

 * bash
 * sed
 * ssh
 * GNU coreutils
   * dirname
   * env
   * mkdir
   * sort
   * stdbuf
   * test

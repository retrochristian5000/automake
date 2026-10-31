#! /bin/sh
# Copyright (C) 1997-2026 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Check basic use of conditionals.

. test-init.sh

cat >> configure.ac << 'END'
AM_CONDITIONAL([TEST], [true])
AC_OUTPUT
END

cat > Makefile.am << 'END'
if TEST
VAR = true
else
VAR = false
endif
END

$ACLOCAL
$AUTOMAKE

grep '^TEST_FALSE' Makefile.in && exit 1
grep '^TEST_TRUE' Makefile.in && exit 1
grep '^@TEST_TRUE@VAR = true$' Makefile.in
grep '^@TEST_FALSE@VAR = false
 Makefile.in

# TRUE and FALSE are reserved condition names.  Diagnose them at M4
# expansion time; the modern diagnostic is m4_fatal, not AC_FATAL.
cat >>configure.ac <<'END'
AM_CONDITIONAL([TRUE], [true])
END
if $AUTOCONF >stdout 2>stderr; then
  echo 'reserved TRUE conditional unexpectedly accepted' >&2
  exit 1
fi
grep 'AM_CONDITIONAL: invalid condition: TRUE' stderr

:

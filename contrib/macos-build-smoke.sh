#!/bin/sh
# Validate the WHP Automake source bootstrap and installation on macOS.
# No Homebrew installations, tracked source writes, or host-wide installs.
set -eu

error()
{
    printf 'WHP Automake macOS: %s\n' "$*" >&2
    exit 1
}

[ "$(uname -s)" = Darwin ] ||
    error 'this smoke test requires a macOS host'
command -v git >/dev/null 2>&1 || error 'git is required'
command -v perl >/dev/null 2>&1 || error 'Perl is required'

root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
[ -f "$root/configure.ac" ] && [ -f "$root/bootstrap" ] ||
    error 'not an Automake source directory'
git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 ||
    error 'a Git checkout is required for bootstrap'

# The seed tools must be a single GNU Autoconf release; a mix of Apple
# /usr/bin and Homebrew prefixes can break the bootstrap.
resolve()
{
    command -v "$1" 2>/dev/null || return 1
}

autoconf=$(resolve "${WHP_AUTOMAKE_SEED_AUTOCONF:-autoconf}") ||
    error 'install GNU Autoconf (e.g. brew install autoconf)'
autom4te=$(resolve "${WHP_AUTOMAKE_SEED_AUTOM4TE:-autom4te}") ||
    error 'matching GNU autom4te is required'
perl=$(resolve "${PERL:-perl}") || error 'Perl is required'
# Homebrew's GNU Make and Texinfo may be keg-only on macOS.
# Discover their installed prefixes instead of trusting /usr/bin/make
# or assuming 'brew install' exposed binaries on PATH.
brew_tool()
{
    [ -n "${1:-}" ] && command -v brew >/dev/null 2>&1 || return 1
    brew_dir=$(brew --prefix "$1" 2>/dev/null) || return 1
    [ -x "$brew_dir/bin/$2" ] || return 1
    printf '%s\n' "$brew_dir/bin/$2"
}
make=
if [ -n "${MAKE:-}" ]; then
    make=$(resolve "$MAKE") || error 'MAKE is unavailable'
else
    for candidate in gmake "$(brew_tool make gmake || true)" make; do
        [ -n "$candidate" ] || continue
        if make=$(resolve "$candidate"); then
            if "$make" --version 2>/dev/null | grep 'GNU Make' >/dev/null; then
                break
            fi
        fi
        make=
    done
fi
[ -n "$make" ] && "$make" --version 2>/dev/null | grep 'GNU Make' >/dev/null ||
    error 'GNU Make is required (e.g. brew install make)'

ac_id=$("$autoconf" --version | sed -n '1p') ||
    error 'Autoconf version probe failed'
a4_id=$("$autom4te" --version | sed -n '1p') ||
    error 'autom4te version probe failed'
case "$ac_id:$a4_id" in
    *'GNU Autoconf'*:*'GNU Autoconf'*) ;;
    *) error "incompatible Autoconf pair: $ac_id / $a4_id" ;;
esac
[ "${ac_id##* }" = "${a4_id##* }" ] ||
    error "seed versions differ: $ac_id / $a4_id"

# Apple /usr/bin/m4 is not assumed to implement GNU M4 semantics.
# Use a private PATH shim so every Autoconf subprocess sees the same M4.
m4=
if [ -n "${M4:-}" ]; then
    m4=$(resolve "$M4") || error 'explicit M4 is not executable'
else
    for candidate in gm4 "$(brew_tool m4 m4 || true)" m4; do
        [ -n "$candidate" ] || continue
        if m4=$(resolve "$candidate"); then
            if "$m4" --gnu --version 2>/dev/null | grep 'GNU M4' >/dev/null; then
                break
            fi
        fi
        m4=
    done
fi
[ -n "$m4" ] && "$m4" --gnu --version 2>/dev/null | grep 'GNU M4' >/dev/null ||
    error 'GNU M4 with --gnu support is required (e.g. brew install m4)'
case "$m4" in
    /*) ;;
    *) error 'M4 must resolve to an absolute executable path' ;;
esac

# A development checkout regenerates doc/automake.info during make.
# macOS does not reliably ship GNU Texinfo's makeinfo in the default PATH.
makeinfo=$(resolve makeinfo || brew_tool texinfo makeinfo || true)
[ -n "$makeinfo" ] ||
    error 'GNU Texinfo makeinfo is required (brew install texinfo)'
case "$makeinfo" in
    /*) ;;
    *) error 'makeinfo must resolve to an absolute executable path' ;;
esac

# Execute against committed source in a disposable clone. The upstream
# bootstrap regenerates source files; never run it in the user's checkout.
work=$(mktemp -d "${TMPDIR:-/tmp}/whp-automake-macos.XXXXXXXX") ||
    error 'cannot allocate temporary build directory'
cleanup()
{
    if [ "${WHP_AUTOMAKE_KEEP_BUILD:-0}" != 1 ]; then rm -rf "$work"; fi
}
trap cleanup 0
trap 'exit 1' 1 2 3 15

mkdir -p "$work/bin" "$work/build"
ln -s "$m4" "$work/bin/m4" || error 'cannot expose GNU M4'
PATH="$work/bin:$(dirname "$makeinfo"):$PATH"
export PATH
M4="$m4"
PERL="$perl"
AUTOCONF="$autoconf"
AUTOM4TE="$autom4te"
export M4 PERL AUTOCONF AUTOM4TE

git clone -q --local --no-hardlinks "$root" "$work/source" ||
    error 'cannot clone Automake source for isolated bootstrap'
pin=$(git -C "$work/source" rev-parse HEAD)
api=$(sed -n 's/^APIVERSION=//p' "$work/source/configure.ac")
[ -n "$api" ] || error 'missing Automake API version'

printf 'WHP Automake macOS: host=%s arch=%s source=%s\n' \
    "$(sw_vers -productVersion)" "$(uname -m)" "$pin"
printf 'WHP Automake macOS: seed=%s; make=%s; m4=%s; perl=%s\n' \
    "$ac_id" "$make" "$m4" "$perl"
printf 'WHP Automake macOS: makeinfo=%s\n' "$makeinfo"

(
    cd "$work/source"
    /bin/sh ./bootstrap
) || error 'bootstrap failed'
[ -f "$work/source/configure" ] ||
    error 'bootstrap did not generate configure'

prefix="$work/install"
(
    cd "$work/build"
    /bin/sh "$work/source/configure" --prefix="$prefix" "PERL=$perl"
    "$make"
    "$make" check TESTS=t/get-sysconf
    "$make" install
) || error 'configure, build, smoke test, or install failed'

[ -x "$prefix/bin/automake" ] && [ -x "$prefix/bin/aclocal" ] ||
    error 'installed executables are missing'
"$prefix/bin/automake" --version | grep 'GNU automake' >/dev/null ||
    error 'installed Automake is not usable'
"$prefix/bin/aclocal" --version | grep 'GNU automake' >/dev/null ||
    error 'installed aclocal is not usable'
# --print-ac-dir reports the *system* macro directory, while
# Automake's own versioned definitions reside in aclocal-$APIVERSION.
acdir=$("$prefix/bin/aclocal" --print-ac-dir) ||
    error 'aclocal cannot locate its system macro directory'
[ "$acdir" = "$prefix/share/aclocal" ] && [ -d "$acdir" ] ||
    error "aclocal selected wrong system macro directory: $acdir"
versioned_acdir="$prefix/share/aclocal-$api"
[ -f "$versioned_acdir/install-sh.m4" ] &&
[ -f "$versioned_acdir/strip.m4" ] ||
    error "installed versioned Automake macros are missing: $versioned_acdir"

printf 'PASS: macOS Automake bootstrap/build/check/install, API %s, %s\n' "$api" "$pin"
if [ "${WHP_AUTOMAKE_KEEP_BUILD:-0}" = 1 ]; then
    printf 'Retained isolated build at %s\n' "$work"
fi

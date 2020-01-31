#!/bin/sh

if [ "$1" != "" ]; then
  AWSTATS_DOWNLOAD="$1"
else
  # set this to the (latest) available version you want:
  AWSTATS_DOWNLOAD="awstats-7.7-1.noarch.rpm"
fi
SKIP_PKG_INSTALL=false
SKIP_PKG_CONVERT=false
SKIP_CONFIG=false
AWSTATS_CRON=/etc/cron.d/awstats
AWSTATS_DEFAULT=/etc/default/awstats
AWSTATS_LOGROTATE=/etc/logrotate.d/httpd-prerotate/awstats/prerotate.sh
AWSTATS_TOOLS=/usr/local/awstats/tools
AWSTATS_APACHE2=/etc/apache2/conf-available/awstats.conf
AWSTATS_LIGHTY=/etc/lighttpd/conf-available/10-cgi.conf

if [ "$( id -u )" -ne 0 ]; then
  echo "Please run this script as root"
  exit 1
fi
if [ -z "$AWSTATS_DOWNLOAD" ]; then
  echo "Error: missing setting \$AWSTATS_DOWNLOAD, exiting ..."
  exit 1
fi
if ! echo "$AWSTATS_DOWNLOAD" | grep -q ".rpm$"; then
  AWSTATS_DOWNLOAD="$AWSTATS_DOWNLOAD.rpm"
fi
if [ ! -f $AWSTATS_DOWNLOAD ]; then
  wget "https://prdownloads.sourceforge.net/awstats/${AWSTATS_DOWNLOAD}" || \
    { echo "Error: could not download \"$AWSTATS_DOWNLOAD\", exiting..."; exit 1 ;}
fi
if [ "$SKIP_PKG_CONVERT" = "true" ]; then
  echo "Skipping package convertion"
else
  if ! dpkg -s alien >/dev/null 2>&1; then
    echo "Please install \"alien\" first using \"apt install alien\""
    echo "It is needed to convert the awstats rpm package to .deb format"
    exit 1
  fi
  if [ "$SKIP_PKG_INSTALL" = "true" ]; then
    echo "Skipping package install"
    if ! alien -d "$AWSTATS_DOWNLOAD"; then
      echo "Converting $AWSTATS_DOWNLOAD to .deb failed, exiting..."
      exit 1
    fi
  else
    if ! alien -d -i "$AWSTATS_DOWNLOAD"; then
      echo "Installing/converting $AWSTATS_DOWNLOAD to .deb failed, exiting..."
      exit 1
    fi
  fi
fi
if [ "$SKIP_CONFIG" = "true" ]; then
  echo "Skipping configuration, exiting..."
  exit 0
fi

if [ -f "$AWSTATS_CRON" ]; then
cat <<'_EOF_' > $AWSTATS_CRON
MAILTO=root

*/10 * * * * root [ -x /usr/local/awstats/tools/update.sh ] && /usr/local/awstats/tools/update.sh

# Generate static reports:
10 03 * * * root [ -x /usr/local/awstats/tools/buildstatic.sh ] && /usr/local/awstats/tools/buildstatic.sh
_EOF_
else
  if [ ! -f "${AWSTATS_CRON}_awconv.bak" ]; then
    sed -i_awconv.bak -e 's@/usr/share/awstats/@/usr/local/awstats/@g' \
                      -e "s/www-data/root/g" $AWSTATS_CRON
  fi
fi
echo
echo "Changed cron to run as root instead of www-data because webserver logs are usually owned by root:adm"
if [ -f "${AWSTATS_CRON}_awconv.bak" ]; then
  echo "This can be reverted by moving ${AWSTATS_CRON}_awconv.bak to ${AWSTATS_CRON}"
fi
echo "If you want to cron as www-data you probably want to change permissions of your webservers log files"
echo

if [ ! -f "$AWSTATS_DEFAULT" ]; then
cat <<'_EOF_' > "$AWSTATS_DEFAULT"
# AWStats configuration options

# This variable controls the scheduling priority for updating AWStats
# datafiles and for generating static html reports.  Normal priority
# is 0 and a lower priority is 10.  See "man nice" for more info.
AWSTATS_NICE=10

# This variable controls whether to create static html reports every
# night in /var/cache/awstats/.  Set to "yes" or "no".
# To enable this you should also set AWSTATS_ENABLE_CRONTABS to "yes".
AWSTATS_ENABLE_BUILDSTATICPAGES="yes"

# This variable controls the language of all static html reports.  Set
# one to appropriate two-letter language code (default to en).
AWSTATS_LANG="en"

# This variable controls whether to run regular cron jobs for awstats.  Set
# to "yes" or "no" (default to "yes").
AWSTATS_ENABLE_CRONTABS="yes"
_EOF_
fi

if [ ! -f "$AWSTATS_LOGROTATE" ]; then
cat <<'_EOF_' > "$AWSTATS_LOGROTATE"
#!/bin/sh
UPDATE_SCRIPT=/usr/local/awstats/tools/update.sh
if [ -x "$UPDATE_SCRIPT" ]
then
  su -l -c "$UPDATE_SCRIPT" www-data
fi
_EOF_
chmod 755 "$AWSTATS_LOGROTATE"
else
  if [ ! -f "${AWSTATS_LOGROTATE}_awconv.bak" ]; then
    sed -i_awconv.bak 's@/usr/share/awstats/@/usr/local/awstats/@g' $AWSTATS_LOGROTATE
  fi
fi

if [ ! -f "$AWSTATS_TOOLS/buildstatic.sh" ]; then
cat <<'_EOF_' > "$AWSTATS_TOOLS/buildstatic.sh"
#!/bin/sh
##
## buildstatic.sh, written by Sergey B Kirpichev <skirpichev@gmail.com>
##
## Build all static html reports from AWStats data (Debian specific)
##

set -e

DEFAULT=/etc/default/awstats
AWSTATS=/usr/local/awstats/wwwroot/cgi-bin/awstats.pl 
BUILDSTATICPAGES=/usr/local/awstats/tools/awstats_buildstaticpages.pl
ERRFILE=`mktemp --tmpdir awstats.XXXXXXXXXX`
YEAR=`date +%Y`
MONTH=`date +%m`

trap 'rm -f $ERRFILE' INT QUIT TERM EXIT

[ -f $AWSTATS -a -f $BUILDSTATICPAGES ] || exit 1

# Set default
AWSTATS_NICE=10
AWSTATS_ENABLE_BUILDSTATICPAGES="yes"
AWSTATS_LANG="en"
[ ! -r "$DEFAULT" ] || . "$DEFAULT"

# For compatibility: handle empty AWSTATS_ENABLE_CRONTABS as "yes":
[ "${AWSTATS_ENABLE_CRONTABS:-yes}" = "yes" -a \
  "$AWSTATS_ENABLE_BUILDSTATICPAGES" = "yes" ] || exit 0

cd /etc/awstats

for c in `/bin/ls -1 awstats.*.conf 2>/dev/null | \
          /bin/sed 's/^awstats\.\(.*\)\.conf/\1/'` \
         `[ -f /etc/awstats/awstats.conf ] && echo awstats`
do
  mkdir -p /var/cache/awstats/$c/$YEAR/$MONTH/

  if ! nice -n $AWSTATS_NICE $BUILDSTATICPAGES \
    -config=$c \
	-year=$YEAR \
	-month=$MONTH \
	-lang=$AWSTATS_LANG \
	-staticlinksext=${AWSTATS_LANG}.html \
	-dir=/var/cache/awstats/$c/$YEAR/$MONTH/ >$ERRFILE 2>&1
  then
    cat $ERRFILE >&2 # an error occurred
  else
    ln -fs /var/cache/awstats/$c/$YEAR/$MONTH/awstats.$c.$AWSTATS_LANG.html \
        /var/cache/awstats/$c/$YEAR/$MONTH/index.$AWSTATS_LANG.html
  fi
done
_EOF_
chmod 755 "$AWSTATS_TOOLS/buildstatic.sh"
fi

if [ ! -f "$AWSTATS_TOOLS/update.sh" ]; then
cat <<'_EOF_' > "$AWSTATS_TOOLS/update.sh"
#!/bin/sh
##
## update.sh, written by Sergey B Kirpichev <skirpichev@gmail.com>
##
## Update AWStats data for all configs, awstats.*.conf (Debian specific)
##

set -e

DEFAULT=/etc/default/awstats
AWSTATS=/usr/local/awstats/wwwroot/cgi-bin/awstats.pl
ERRFILE=`mktemp --tmpdir awstats.XXXXXXXXXX`

trap 'rm -f $ERRFILE' INT QUIT TERM EXIT

[ -f $AWSTATS ] || exit 1

# Set defaults.
AWSTATS_NICE=10
[ ! -r "$DEFAULT" ] || . "$DEFAULT"

# For compatibility: handle empty AWSTATS_ENABLE_CRONTABS as "yes":
[ "${AWSTATS_ENABLE_CRONTABS:-yes}" = "yes" ] || exit 0

cd /etc/awstats

for c in `/bin/ls -1 awstats.*.conf 2>/dev/null | \
          /bin/sed 's/^awstats\.\(.*\)\.conf/\1/'` \
         `[ -f /etc/awstats/awstats.conf ] && echo awstats`
do
  if ! nice -n $AWSTATS_NICE $AWSTATS \
	  -config=$c \
	  -update >$ERRFILE 2>&1
  then
    echo "Error while processing" \
         "/etc/awstats/awstats$(test $c != awstats && echo .$c).conf" >&2
    cat $ERRFILE >&2 # an error occurred
  fi
done
_EOF_
chmod 755 "$AWSTATS_TOOLS/update.sh"
fi

if [ -f /etc/awstats/awstats.model.conf ]; then gzip /etc/awstats/awstats.model.conf; fi

if dpkg -s apache2 >/dev/null 2>&1; then
  if [ ! -f "$AWSTATS_APACHE2" ]; then
cat <<'_EOF_' > "$AWSTATS_APACHE2"
#
# Directives to allow use of AWStats as a CGI
#
# This provides worldwide access to everything below the directory
# Security concerns:
#  * Raw log processing data is accessible too for everyone
#  * The directory is by default writable by the httpd daemon, so if
#    any PHP, CGI or other script can be tricked into copying or
#    symlinking stuff here, you have a looking glass into your server,
#    and if stuff can be uploaded to here, you have a public warez site!
<Directory /var/lib/awstats>
        Options None
        AllowOverride None
        Require ip 127.0.0.1
</Directory>

# This provides worldwide access to everything below the directory
# Security concerns: none known
<Directory /usr/local/awstats/wwwroot/icon>
        Options None
        AllowOverride None
        Require all granted
</Directory>

# This provides worldwide access to everything below the directory
# Security concerns: none known
<Directory /usr/local/awstats/wwwroot/classes>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>

<Directory /usr/local/awstats/wwwroot>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>

# This provides worldwide access to everything in the directory
# Security concerns: none known
Alias /awstats-icon/ /usr/local/awstats/wwwroot/icon/

# This provides worldwide access to everything in the directory
# Security concerns: none known
Alias /awstatsclasses/ /usr/share/awstats/wwwroot/classes/

# This (hopefully) enables _all_ CGI scripts in the default directory
# Security concerns: Are you sure _all_ CGI scripts are safe?
#ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
ScriptAlias /awstats/ /usr/local/awstats/wwwroot/cgi-bin/
_EOF_
else
  if [ ! -f "${AWSTATS_APACHE2}_awconv.bak" ]; then
    sed -i_awconv.bak -e 's@<Directory /usr/share/awstats/icon>@<Directory /usr/local/awstats/wwwroot/icon>@' \
                      -e 's@<Directory /usr/share/java/awstats>@<Directory /usr/local/awstats/wwwroot/classes>@g' \
                      -e 's@<Directory /var/www/html/awstats>@<Directory /usr/local/awstats/wwwroot>@g' \
                      -e 's@Alias /awstats-icon/ /usr/share/awstats/icon/@Alias /awstats-icon/ /usr/local/awstats/wwwroot/icon/@g' \
                      -e 's@Alias /awstatsclasses/ /usr/share/java/awstats/@Alias /awstatsclasses/ /usr/local/awstats/wwwroot/classes/@g' \
                      -e 's@ScriptAlias /awstats/ /usr/lib/cgi-bin/@ScriptAlias /awstats/ /usr/local/awstats/wwwroot/cgi-bin/@g' \
    "$AWSTATS_APACHE2" && {
      a2enconf awstats || echo "Error: running a2enconf awstats failed" && {
        service apache2 reload || echo "Error: could not reload apache2 service"
      }
    }
  fi
fi
elif dpkg -s lighttpd >/dev/null 2>&1; then
  if [ ! -f "${AWSTATS_LIGHTY}_awconv.bak" ]; then
    sed -i_awconv.bak -e 's@"/awstatsclasses/" => "/usr/share/java/awstats/"@"/awstatsclasses/" => "/usr/local/awstats/wwwroot/classes/"@g' \
                      -e 's@"/awstatscss/" => "/usr/share/doc/awstats/examples/css/"@"/awstatscss/" => "/usr/local/awstats/wwwroot/css/"@g' \
                      -e 's@"/awstatsicons/" => "/usr/share/awstats/icon/"@"/awstatsicons/" => "/usr/local/awstats/wwwroot/icon/"@' \
                      -e 's@"/awstats-icon/" => "/usr/share/awstats/icon/"@"/awstats-icon/" => "/usr/local/awstats/wwwroot/icon/"@g' \
                      -e 's@"/awstats/" => "/usr/lib/cgi-bin/"@"/awstats/" => "/usr/local/awstats/wwwroot/cgi-bin/"@g' \
                      -e 's@"/icon/" => "/usr/share/awstats/icon/"@"/icon/" => "/usr/local/awstats/wwwroot/icon/"@g' \
                      -e 's@"/cgi-bin/" => "/usr/lib/cgi-bin/"@"/cgi-bin/" => "/usr/local/awstats/wwwroot/cgi-bin/"@g' \
    "$AWSTATS_LIGHTY" && {
      service lighttpd reload || echo "Error: could not reload lighttpd service"
    }     
  fi
else
  echo "Make sure to configure your webserver for AWStats"
fi

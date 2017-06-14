#!/bin/sh

if [ "$1" != "" ]; then
  AWSTATS_DOWNLOAD=$1
else
  # set this to the (latest) available version you want:
  AWSTATS_DOWNLOAD=awstats-7.6-1.noarch
fi
SKIP_PKG_INSTALL=false
AWSTATS_APACHE2=/etc/apache2/conf-available/awstats.conf
AWSTATS_CRON=/etc/cron.d/awstats
AWSTATS_DEFAULT=/etc/default/awstats
AWSTATS_LOGROTATE=/etc/logrotate.d/httpd-prerotate/awstats/prerotate.sh
AWSTATS_TOOLS=/usr/local/awstats/tools

if [ $( id -u ) -ne 0 ]; then
  echo "please run this script as root"
  exit 1
fi
if [ ! -f $AWSTATS_DOWNLOAD.rpm ]; then
  wget https://prdownloads.sourceforge.net/awstats/$AWSTATS_DOWNLOAD.rpm
fi
dpkg -l alien >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "please install \"alien\" package first using \"apt install alien\""
  echo "it is needed to convert awstats pkg from .rpm to .deb"
  exit 1
fi
if [ ! "$SKIP_PKG_INSTALL" = "true" ]; then
  alien -d -i $AWSTATS_DOWNLOAD.rpm
  if [ $? -ne 0 ]; then
    echo "installing/converting $AWSTATS_DOWNLOAD.rpm to .deb failed"
    exit 1
  fi 
fi

if [ -f $AWSTATS_CRON ]; then
cat <<'_EOF_' > $AWSTATS_CRON
MAILTO=root

*/10 * * * * root [ -x /usr/local/awstats/tools/update.sh ] && /usr/local/awstats/tools/update.sh

# Generate static reports:
10 03 * * * root [ -x /usr/local/awstats/tools/buildstatic.sh ] && /usr/local/awstats/tools/buildstatic.sh
_EOF_
else
  if [ ! -f ${AWSTATS_CRON}_awconv.bak ]; then
    sed -i_awconv.bak -e 's@/usr/share/awstats/@/usr/local/awstats/@g' \
                      -e "s/www-data/root/g" $AWSTATS_CRON
  fi
fi
echo
echo "changed cron to run as root instead of www-data because apache logs are usually owned by root:adm"
echo
echo "this can be reverted by moving ${AWSTATS_CRON}_awconv.bak to ${AWSTATS_CRON}"
echo "if you decide to do this you probably want to change permissions of the apache log files"
echo

if [ ! -f $AWSTATS_DEFAULT ]; then
cat <<'_EOF_' > $AWSTATS_DEFAULT
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

if [ ! -f $AWSTATS_LOGROTATE ]; then
cat <<'_EOF_' > $AWSTATS_LOGROTATE
#!/bin/sh
UPDATE_SCRIPT=/usr/local/awstats/tools/update.sh
if [ -x $UPDATE_SCRIPT ]
then
  su -l -c $UPDATE_SCRIPT www-data
fi
_EOF_
chmod 755 $AWSTATS_LOGROTATE
else
  if [ ! -f ${AWSTATS_APACHE2}_awconv.bak ]; then
    sed -i_awconv.bak 's@/usr/share/awstats/@/usr/local/awstats/@g' $AWSTATS_LOGROTATE
  fi
fi

if [ ! -f $AWSTATS_TOOLS/buildstatic.sh ]; then
cat <<'_EOF_' > $AWSTATS_TOOLS/buildstatic.sh
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
chmod 755 $AWSTATS_TOOLS/buildstatic.sh
fi

if [ ! -f $AWSTATS_TOOLS/update.sh ]; then
cat <<'_EOF_' > $AWSTATS_TOOLS/update.sh
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
chmod 755 $AWSTATS_TOOLS/update.sh
fi

if [ ! -f $AWSTATS_APACHE2 ]; then
cat <<'_EOF_' > $AWSTATS_APACHE2
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
  if [ ! -f ${AWSTATS_APACHE2}_awconv.bak ]; then
    sed -i_awconv.bak -e 's@<Directory /usr/share/awstats/icon>@<Directory /usr/local/awstats/wwwroot/icon>@' \
                      -e 's@<Directory /usr/share/java/awstats>@<Directory /usr/local/awstats/wwwroot/classes>@g' \
                      -e 's@<Directory /var/www/html/awstats>@<Directory /usr/local/awstats/wwwroot>@g' \
                      -e 's@Alias /awstats-icon/ /usr/share/awstats/icon/@Alias /awstats-icon/ /usr/local/awstats/wwwroot/icon/@g' \
                      -e 's@Alias /awstatsclasses/ /usr/share/java/awstats/@Alias /awstatsclasses/ /usr/local/awstats/wwwroot/classes/@g' \
                      -e 's@ScriptAlias /awstats/ /usr/lib/cgi-bin/@ScriptAlias /awstats/ /usr/local/awstats/wwwroot/cgi-bin/@g' \
    $AWSTATS_APACHE2 && a2enconf awstats
  fi
fi
service apache2 reload
if [ -f /etc/awstats/awstats.model.conf ]; then gzip /etc/awstats/awstats.model.conf; fi

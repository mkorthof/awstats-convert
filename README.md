# AWStats Convert
## Converts AWStats rpm package to .deb format

This script downloads the (latest) version of the AWStats rpm package and converts/installs it to .deb using a tool called "alien". It also applies correct Debian configuration (logrotate, cron and apache).

Reason being awstats only has rpm packages available for download and the latest version isn't always immediately available for Debian elsewhere. Preferred package as src because it installs to correct dir structure and includes configuration.

Run as root
```
./awstats_conv.sh [package]
./awstats_conv.sh awstats-7.6-1.noarch
```
* without argument it will use ```AWSTATS_DOWNLOAD``` variable
* to download it runs ```wget https://prdownloads.sourceforge.net/awstats/$AWSTATS_DOWNLOAD.rpm```
* set ```SKIP_PKG_INSTALL``` to true to skip running alien and config only

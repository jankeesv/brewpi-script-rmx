#!/bin/bash

# Copyright (C) 2018, 2019 Lee C. Bussy (@LBussy)

# This file is part of LBussy's BrewPi Script Remix (BrewPi-Script-RMX).
#
# BrewPi Script RMX is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# BrewPi Script RMX is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with BrewPi Script RMX. If not, see <https://www.gnu.org/licenses/>.

# These scripts were originally a part of brewpi-script, a part of
# the BrewPi project. Legacy support (for the very popular Arduino
# controller) seems to have been discontinued in favor of new hardware.

# All credit for the original brewpi-script goes to @elcojacobs,
# @m-mcgowan, @rbrady, @steersbob, @glibersat, @Niels-R and I'm sure
# many more contributors around the world. My apologies if I have
# missed anyone; those were the names listed as contributors on the
# Legacy branch.

# See: 'original-license.md' for notes about the original project's
# license and credits.

# Declare this script's constants
declare SCRIPTPATH GITROOT APTPACKAGES NGINXPACKAGES PIPPACKAGES
# Declare /inc/const.inc file constants
declare THISSCRIPT SCRIPTNAME VERSION GITROOT GITURL GITPROJ PACKAGE
# Declare /inc/asroot.inc file constants
declare HOMEPATH REALUSER

############
### Init
############

init() {
    # Change to current dir (assumed to be in a repo) so we can get the git info
    pushd . &> /dev/null || exit 1
    SCRIPTPATH="$( cd "$(dirname "$0")" || exit 1 ; pwd -P )"
    cd "$SCRIPTPATH" || exit 1 # Move to where the script is
    GITROOT="$(git rev-parse --show-toplevel)" &> /dev/null
    if [ -z "$GITROOT" ]; then
        echo -e "\nERROR: Unable to find my repository, did you move this file or not run as root?"
        popd &> /dev/null || exit 1
        exit 1
    fi
    
    # Get project constants
    # shellcheck source=/dev/null
    . "$GITROOT/inc/const.inc" "$@"
    
    # Get error handling functionality
    # shellcheck source=/dev/null
    . "$GITROOT/inc/error.inc" "$@"
    
    # Get help and version functionality
    # shellcheck source=/dev/null
    . "$GITROOT/inc/asroot.inc" "$@"
    
    # Get help and version functionality
    # shellcheck source=/dev/null
    . "$GITROOT/inc/help.inc" "$@"
    
    # Read configuration
    # shellcheck source=/dev/null
    . "$GITROOT/inc/config.inc" "$@"
    
    # Check network connectivity
    # shellcheck source=/dev/null
    . "$GITROOT/inc/nettest.inc" "$@"
    
    # Packages to be installed/checked via apt
    APTPACKAGES="git arduino-core git-core pastebinit build-essential apache2 libapache2-mod-php php-cli php-common php-cgi php php-mbstring python-dev python-pip python-configobj php-xml bluez python-bluez python-scipy python-numpy libcap2-bin"
    # nginx packages to be uninstalled via apt if present
    NGINXPACKAGES="libgd-tools fcgiwrap nginx-doc ssl-cert fontconfig-config fonts-dejavu-core libfontconfig1 libgd3 libjbig0 libnginx-mod-http-auth-pam libnginx-mod-http-dav-ext libnginx-mod-http-echo libnginx-mod-http-geoip libnginx-mod-http-image-filter libnginx-mod-http-subs-filter libnginx-mod-http-upstream-fair libnginx-mod-http-xslt-filter libnginx-mod-mail libnginx-mod-stream libtiff5 libwebp6 libxpm4 libxslt1.1 nginx nginx-common nginx-full"
    # Packages to be installed/check via pip
    PIPPACKAGES="pyserial psutil simplejson configobj gitpython"
}

############
### Create a banner
############

banner() {
    local adj
    adj="$1"
    echo -e "\n***Script $THISSCRIPT $adj.***"
}

############
### Check last apt update date
############

apt_check() {
    # Run 'apt update' if last run was > 1 week ago
    lastUpdate=$(stat -c %Y /var/lib/apt/lists)
    nowTime=$(date +%s)
    if [ $(($nowTime - $lastUpdate)) -gt 604800 ] ; then
        echo -e "\nLast apt update was over a week ago. Running apt update before updating"
        echo -e "dependencies."
        apt-get update -q||die
        echo
    fi
}

############
### Remove php5 packages if installed
############

rem_php5() {
    echo -e "\nChecking for previously installed php5 packages."
    # Get list of installed packages
    php5packages="$(dpkg --get-selections | awk '{ print $1 }' | grep 'php5')"
    if [[ -z "$php5packages" ]] ; then
        echo -e "\nNo php5 packages found."
    else
        echo -e "\nFound php5 packages installed.  It is recomended to uninstall all php before"
        echo -e "proceeding as BrewPi requires php7 and will install it during the install"
        read -p "process.  Would you like to clean this up before proceeding?  [Y/n]: " yn  < /dev/tty
        case $yn in
            [Nn]* )
                echo -e "\nUnable to proceed with php5 installed, exiting.";
            exit 1;;
            * )
                php_packages="$(dpkg --get-selections | awk '{ print $1 }' | grep 'php')"
                # Loop through the php5 packages that we've found
                for pkg in ${php_packages,,}; do
                    echo -e "\nRemoving '$pkg'.\n"
                    sudo apt-get remove --purge $pkg -y -q=2
                done
                echo -e "\nCleanup of the php environment complete."
            ;;
        esac
    fi
}

############
### Remove nginx packages if installed
############

rem_nginx() {
    echo -e "\nChecking for previously installed nginx packages."
    # Get list of installed packages
    nginxPackage="$(dpkg --get-selections | awk '{ print $1 }' | grep 'nginx')"
    if [[ -z "$nginxPackage" ]] ; then
        echo -e "\nNo nginx packages found."
    else
        echo -e "\nFound nginx packages installed.  It is recomended to uninstall nginx before"
        echo -e "proceeding as BrewPi requires apache2 and they will conflict with each other."
        read -p "Would you like to clean this up before proceeding?  [Y/n]: " yn  < /dev/tty
        case $yn in
            [Nn]* )
                echo -e "\nUnable to proceed with nginx installed, exiting.";
            exit 1;;
            * )
                # Loop through the php5 packages that we've found
                for pkg in ${NGINXPACKAGES,,}; do
                    echo -e "\nRemoving '$pkg'.\n"
                    sudo apt-get remove --purge $pkg -y -q=2
                done
                echo -e "\nCleanup of the nginx environment complete."
            ;;
        esac
    fi
}

############
### Install and update required packages
############

do_packages() {
    # Now install any necessary packages if they are not installed
    echo -e "\nChecking and installing required dependencies via apt."
    for pkg in ${APTPACKAGES,,}; do
        pkgOk=$(dpkg-query -W --showformat='${Status}\n' ${pkg,,} | \
        grep "install ok installed")
        if [ -z "$pkgOk" ]; then
            echo -e "\nInstalling '$pkg'.\n"
            apt-get install ${pkg,,} -y -q=2||die
            echo
        fi
    done
    
    # Get list of installed packages with upgrade available
    upgradesAvail=$(dpkg --get-selections | xargs apt-cache policy {} | \
        grep -1 Installed | sed -r 's/(:|Installed: |Candidate: )//' | \
    uniq -u | tac | sed '/--/I,+1 d' | tac | sed '$d' | sed -n 1~2p)
    
    # Loop through only the required packages and see if they need an upgrade
    for pkg in ${APTPACKAGES,,}; do
        if [[ ${upgradesAvail,,} == *"$pkg"* ]]; then
            echo -e "\nUpgrading '$pkg'.\n"
            apt-get install ${pkg,,} -y -q=2||die
            doCleanup=1
        fi
    done
    
    # Cleanup if we updated packages
    if [ -n "$doCleanup" ]; then
        echo -e "\nCleaning up local repositories."
        apt clean -y||warn
        apt autoclean -y||warn
        apt autoremove --purge -y||warn
    else
        echo -e "\nNo apt updates to apply."
    fi
    
    # Install any Python packages not installed, update those installed
    echo -e "\nChecking and installing required dependencies via pip."
    pipcmd='pipInstalled=$(pip list --format=columns)'
    eval "$pipcmd"
    pipcmd='pipInstalled=$(echo "$pipInstalled" | cut -f1 -d" ")'
    eval "$pipcmd"
    for pkg in ${PIPPACKAGES,,}; do
        if [[ ! ${pipInstalled,,} == *"$pkg"* ]]; then
            echo -e "\nInstalling '$pkg'."
            pip install $pkg -q||die
        else
            echo -e "\nChecking for update to '$pkg'."
            pip install $pkg --upgrade -q||die
        fi
    done
}

main() {
    init "$@" # Init and call supporting libs
    const "$@" # Get script constants
    asroot # Make sure we are running with root privs
    help "$@" # Handle help and version requests
    banner "starting"
    apt_check # Check on apt packages
    rem_php5 # Remove php5 packages
    rem_nginx # Remove nginx packages
    do_packages # Check on pip packahes
    banner "complete"
}

main "$@" && exit 0

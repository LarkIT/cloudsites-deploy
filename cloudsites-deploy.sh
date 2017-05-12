#!/bin/bash

# NOTE: this script requires "DOMAIN" to be set and requires composer.
# Composer usually requires git/hg/svn/etc and of course php.
# It is fairly specific to CLOUD SITES, but wouldn't be hard to customize.
# It is designed to be run as part of a Jenkins job.
#  source ~/bin/cloudsites-deploy.sh

# REQUIRED ENVIRONMENT VARIABLES
# - DOMAIN = thedomain.com - used to determine the deployment path
# - HTACCESS_FILE = /path/to/htaccess - deployed as .htaccess (use config file in jenkins)
# - ENV_FILE = /path/to/secret/env - deployed as .env (used for secrets)
# - CREDS = user:passwd - sftp server credentials (password can be "dummy" if keys are used)

# OPTIONAL ENVIRONMENT VARIABLES
# - SERVER = the-envapp-01.domain.com - server to upload files to (default: ftp3.ftptoyoursite.com)
# - DEST = path/to/deploy/to - overrides "determined" path (default: $DOMAIN/web/content)
# - USE_RSYNC = if this variable is non-empty, we will use rsync instead of lftp 
########################

# DETERMINE DEPLOYMENT PATH (top level domains have www. prefixed in Cloud Sites)
if [[ -z $DEST ]]; then
  DOTS=$(_TMPDOTS=${DOMAIN//[^.]}; echo ${#_TMPDOTS})
  if [ $DOTS -gt 1 ]; then
    DEST="/${DOMAIN}/web/content"
  elif [ $DOTS -eq 1 ]; then
    DEST="/www.${DOMAIN}/web/content"
  else
    echo "You probably need to set the DOMAIN parameter!"
    exit 1
  fi
fi

# Default SERVER for cloud sites
[[ -z $SERVER ]] && SERVER='ftp3.ftptoyoursite.com'

# Run Composer
if [ -f "composer.json" ]; then
  echo "Running Composer..."
  if [ -d "vendor" ]; then
    /usr/local/bin/composer update --no-interaction --no-dev
  else
    /usr/local/bin/composer install --no-interaction --no-dev 
  fi
else
  echo "NO composer.json found, not running composer!"
  echo "FAILING!"
  exit 1
fi

# Create .htaccess
cp "$HTACCESS_FILE" .htaccess

# Handle .redirects
[ -f .redirects ] && cat .redirects >> .htaccess

# Ensure files are group writable (workaround for multi-sftp access)
chmod -R u=rwX,g=rwX .

# Get .env file
cp "$ENV_FILE" .env

# Excludes
EXCLUDES=$(grep wp-content .gitignore | grep -v 'wp-content/plugins' | sed -e 's#^/#--exclude #' | tr '\n\r' ' ')

# Sync files to SERVER
if [[ -z $USE_RSYNC ]]; then
#  set +x # Don't put password in logs
  echo "Starting File Sync..."
  lftp -u "${CREDS}" sftp://${SERVER}/ -e "
    mirror --delete --reverse --parallel=10 --exclude .redirects --exclude .git --exclude .gitignore $EXCLUDES . $DEST;
    chmod 600 ${DEST}/.env;
    put -O ${DEST} .env .htaccess;"
else
  rsync --archive --verbose --human-readable --stats --itemize-changes --exclude .redirects --exclude .git --exclude .gitignore $EXCLUDES ./ "${SERVER}:${DEST}/"
fi

# Remove .env file
rm -f .env



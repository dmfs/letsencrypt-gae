#!/bin/bash

# domain of this app engine instance
DOMAIN=$1

# admin email address
export EMAIL=$2

# the path to the yaml file
export CONFIG_FILE=$3

# the name of the repo containing the project sources
export REPO_NAME=${4:-default}

# directory where all the config and temporary files are stored
LE_ROOT=.letsencrypt-gae

# this is where we install the let's encrypt client
LETSENCRYPT_PATH=${LE_ROOT}/letsencrypt

# don't run letsencrypt as root
export LE_AUTO_SUDO=''

# create work, config and log directories
mkdir -p ${LE_ROOT}/{config,work,log,temp} || exit 1

export TEMP_DIR=${LE_ROOT}/temp

# create auth-hook script
cat > $TEMP_DIR/auth-hook.sh << 'EOF'
#!/bin/bash

# clone the project sources
REPO="https://source.developers.google.com/p/${DEVSHELL_PROJECT_ID}/r/${REPO_NAME}"
echo "cloning ${REPO} to ${TEMP_DIR}/repo …"
git clone ${REPO} ${TEMP_DIR}/repo || exit 1

# enter the repo
pushd ${TEMP_DIR}/repo

# go where the challenges are stored
pushd acmechallenge

# update the challenges
echo -n "${CERTBOT_VALIDATION}" > "./${CERTBOT_TOKEN}" || exit 1

echo "pushing validation code …"
# submit changes
git config user.email "${EMAIL}" || exit 1
git config user.name "${USER} for ${DEVSHELL_PROJECT_ID}" || exit 1
git add "./${CERTBOT_TOKEN}" || exit 1
git commit --author=$EMAIL -m "update acme-challenge for letsencrypt certificate renewal" || exit 1
git push || exit 1

# go to project root
popd

# deploy changes
echo "deploying changes …"
appcfg.py update ${CONFIG_FILE} || exit 1

popd
# clean up
echo "cleaning up - removing ${TEMP_DIR}/repo"
rm -rf ${TEMP_DIR}/repo || exit 1
EOF

chmod +x $TEMP_DIR/auth-hook.sh


# get the letsencrypt client
echo "installing letsencrypt client …"
git clone https://github.com/letsencrypt/letsencrypt ${LETSENCRYPT_PATH} || exit 1

# create the certificate
echo "requesting certificate"
${LETSENCRYPT_PATH}/letsencrypt-auto \
   certonly \
   --manual \
   --manual-auth-hook $TEMP_DIR/auth-hook.sh \
   -d $DOMAIN \
   -m $EMAIL \
   --agree-tos \
   --config-dir $LE_ROOT/config \
   --work-dir $LE_ROOT/work \
   --logs-dir $LE_ROOT/log || exit 1


# check if we already have a certificate for this domain
CERT_ID=`gcloud beta app ssl-certificates list | grep "$DOMAIN" | cut -d " " -f 1`
if [ -n "$CERT_ID" ]; then
   echo "updating certificate with ID ${CERT_ID}"
   gcloud \
       beta \
       app \
       ssl-certificates \
       update $CERT_ID \
       --certificate ${LE_ROOT}/config/live/${DOMAIN}/fullchain.pem \
       --private-key ${LE_ROOT}/config/live/${DOMAIN}/privkey.pem || exit 1
else
   echo "installing certificate"
   gcloud \
       beta \
       app \
       ssl-certificates \
       create \
       --display-name "cert-${DOMAIN}" \
       --certificate $LE_ROOT/config/live/${DOMAIN}/fullchain.pem \
       --private-key $LE_ROOT/config/live/${DOMAIN}/privkey.pem || exit 1
fi

# clean up
echo "cleaning up"
rm -rf ${LETSENCRYPT_PATH}


#!/bin/bash

# domain of this app engine instance
DOMAIN=$1

# admin email address
export EMAIL=$2

export CONFIG_FILE=$3

#
export REPO_NAME=${4:-default}

# directory where all the config and temporary files are stored
LE_ROOT=.letsencrypt-gae

# this is where we install the lets' encrypt client
LETSENCRYPT_PATH=./${LE_ROOT}/letsencrypt

# don't run letsencrypt as root
export LE_AUTO_SUDO=''

# create work, config and log directories
mkdir -p ${LE_ROOT}/{config,work,log,temp}

export TEMP_DIR=${LE_ROOT}/temp


# create auth-hook script
cat > $TEMP_DIR/auth-hook.sh << 'EOF'
#!/bin/bash

# clone the project sources
git clone  "https://source.developers.google.com/p/${DEVSHELL_PROJECT_ID}/r/${REPO_NAME}" ${TEMP_DIR}/repo

# enter the repo
pushd ${TEMP_DIR}/repo

# go where the challenges are stored
pushd acmechallenge

# update the challenges
echo -n "${CERTBOT_VALIDATION}" > "./${CERTBOT_TOKEN}"

# submit changes
git config user.email "${EMAIL}"
git config user.name "${USER} for ${DEVSHELL_PROJECT_ID}"
git add "./${CERTBOT_TOKEN}"
git commit --author=$EMAIL -m "update acme-challenge for letsencrypt certificate renewal"
git push

# go to project root
popd

# deploy changes
appcfg.py update ${CONFIG_FILE}

popd
# clean up
rm -rf ${TEMP_DIR}/repo
EOF

chmod +x $TEMP_DIR/auth-hook.sh


# get the letsencrypt client
git clone https://github.com/letsencrypt/letsencrypt ${LETSENCRYPT_PATH}

# create the certificate
${LETSENCRYPT_PATH}/letsencrypt-auto \
   certonly \
   --manual \
   --manual-auth-hook $TEMP_DIR/auth-hook.sh \
   -d $DOMAIN \
   -m $EMAIL \
   --agree-tos \
   --config-dir $LE_ROOT/config \
   --work-dir $LE_ROOT/work \
   --logs-dir $LE_ROOT/log


# check if we already have a certificate for this domain
CERT_ID=`gcloud beta app ssl-certificates list | grep "$DOMAIN" | cut -d " " -f 1`
if [ -n "$CERT_ID" ]; then
   gcloud beta app ssl-certificates update $CERT_ID --certificate ${LE_ROOT}/config/live/$DOMAIN/fullchain.pem --private-key ${LE_ROOT}/config/live/$DOMAIN/privkey.pem
else
   gcloud beta app ssl-certificates create --display-name "cert-$DOMAIN" --certificate $LE_ROOT/config/live/$DOMAIN/fullchain.pem --private-key $LE_ROOT/config/live/$DOMAIN/privkey.pem
fi

# clean up
rm -rf ${LETSENCRYPT_PATH}


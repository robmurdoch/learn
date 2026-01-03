@REM Following https://openssl-ca.readthedocs.io/en/latest/create-the-root-pair.html
@REM Prepare the root directory
@REM Using WSL rober was the root folder
mkdir ca
cd ca
cd rootca
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
cd ..

@REM Prepare the configuration file See the .conf file. Diff against above webpage.

@REM Create the root key ()
openssl genrsa -aes256 -out rootca/private/ca.key.pem 4096
sudo chmod 400 rootca/private/ca.key.pem

@REM Create the root certificate using that private key 
openssl req -config rootca/openssl.cnf -key rootca/private/ca.key.pem -new -x509 -days 7300 -sha256 -extensions v3_ca -out rootca/certs/ca.cert.pem
sudo chmod 444 rootca/certs/ca.cert.pem


@REM Verify the root certificate
openssl x509 -noout -text -in rootca/certs/ca.cert.pem
openssl x509 -in rootca/certs/ca.cert.pem -out rootca/certs/ca.cert.crt

@REM TODO open the .crt file and import the cert to windows trusted root authority



@REM Create the intermediate pair
@REM Prepare the intermediate directory
mkdir intermediateca
cd intermediateca
mkdir certs crl csr newcerts private
sudo chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber
cd ..

@REM Copy the root CAs openssl configuration to intermetidate ca and edit
cp rootca/openssl.cnf intermediateca/openssl.cnf
@REM [ CA_default ]
@REM # Directory and file locations.
@REM dir               = intermediateca
@REM private_key       = $dir/private/intermediate.key.pem
@REM certificate       = $dir/certs/intermediate.cert.pem
@REM crl               = $dir/crl/intermediate.crl.pem
@REM policy            = policy_loose
@REM copy_extensions   = copy

@REM Create the intermediate key ()
openssl genrsa -aes256 -out intermediateca/private/intermediate.key.pem 4096
sudo chmod 400 intermediateca/private/intermediate.key.pem

@REM Create the intermediate certificate USING THE INTERMEDIATE CA config
@REM Create the CSR
openssl req -config intermediateca/openssl.cnf -new -sha256 -key intermediateca/private/intermediate.key.pem -out intermediateca/csr/intermediate.csr.pem

@REM Issue the Cert USING ROOT CA Config
openssl ca -config rootca/openssl.cnf -extensions v3_intermediate_ca -days 3650 -notext -md sha256 -in intermediateca/csr/intermediate.csr.pem -out intermediateca/certs/intermediate.cert.pem

@REM Verify the Cert
openssl x509 -noout -text -in intermediateca/certs/intermediate.cert.pem
openssl verify -CAfile rootca/certs/ca.cert.pem intermediateca/certs/intermediate.cert.pem
openssl x509 -in intermediateca/certs/intermediate.cert.pem -out intermediateca/certs/intermediate.cert.crt

@REM Create a Certificate Chain File
cat intermediateca/certs/intermediate.cert.pem rootca/certs/ca.cert.pem > intermediateca/certs/ca-chain.cert.pem
chmod 444 intermediateca/certs/ca-chain.cert.pem

@REM Now we have an intermetidate CA, we can add the ca.cert.pem to the trusted root authority and the intermediate.ca.pem to the trusted intermediate ca. 

@REM We the CA deployed, we can issue certs for home lab devices. 
@REM We also learn how to request certificates for public facing sites from existing certificate authorities like Digicert, Thawte, Let's Encrypt, etc.

@REM Create a Key (minus -aes256 so users don't have to enter the pwd to use the key). 
@REM Note, in this experiment, we know the private key. In the real world, only the party requesting a cert knows its private key.
mkdir thirdparty
cd thirdparty
mkdir csr private
sudo chmod 700 private
cd ..
@REM Using Internal. See https://en.wikipedia.org/wiki/.internal
openssl genrsa -out thirdparty/private/truenas.key.pem 2048
chmod 400 thirdparty/private/truenas.key.pem
openssl req -config intermediateca/openssl.cnf -key thirdparty/private/truenas.key.pem -new -sha256 -out thirdparty/csr/truenas.blueal.internal.csr.pem -addext "subjectAltName = DNS:tn.blueal.internal"

@REM From the perspective of the CA, Sign the CSR using the Intermediate CA
openssl ca -config intermediateca/openssl.cnf -extensions server_cert -days 375 -notext -md sha256 -in thirdparty/csr/truenas.blueal.internal.csr.pem -out intermediateca/certs/truenas.blueal.internal.cert.pem

@REM Verify the Cert
openssl x509 -noout -text -in intermediateca/certs/truenas.blueal.internal.cert.pem
openssl verify -CAfile intermediateca/certs/ca-chain.cert.pem intermediateca/certs/truenas.blueal.internal.cert.pem
openssl x509 -in intermediateca/certs/truenas.blueal.internal.cert.pem -out intermediateca/certs/truenas.blueal.internal.cert.crt

@REM Bundle it up
cat intermediateca/certs/truenas.blueal.internal.cert.crt intermediateca/certs/intermediate.cert.crt rootca/certs/ca.cert.crt
openssl x509 -in intermediateca\certs\ca-chain.cert.pem -out intermediateca/certs/ca-chain.cert.crt
openssl pkcs12 -export -inkey thirdparty/private/truenas.key.pem -in truenas.blueal.internal.cert.fullchain.crt -out truenas.blueal.internal.cert.fullchain.pfx -name "TrueNas-BlueAl-Internal"
openssl pkcs12 -export -out intermediateca/certs/client.full.pfx -inkey intermediateca/private/intermediate.key.pem -in intermediateca/certs/truenas.blueal.internal.cert.pem -certfile intermediateca/certs/ca-chain.cert.pem -certfile rootca/certs/ca.cert.pem
#!/usr/bin/env bash
[[ -d work ]] && rm -r work
mkdir work
pushd work

openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out ca.key
openssl req -x509 -new -nodes -key ca.key -sha512 -days 30 -subj "/CN=example-selfsigned-ca" -out ca.crt
openssl req -new -nodes -out queuemanager.csr -newkey rsa:4096 -keyout queuemanager.key -subj '/CN=queuemanager'
openssl x509 -req -in queuemanager.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out queuemanager.crt -days 3650 -sha512

oc delete secret queuemanager
oc create secret generic queuemanager --type="kubernetes.io/tls" --from-file=tls.key=queuemanager.key --from-file=tls.crt=queuemanager.crt --from-file=ca.crt


openssl req -new -nodes -out qm-client.csr -newkey rsa:4096 -keyout qm-client.key -subj '/CN=qm-client'
openssl x509 -req -in qm-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out qm-client.crt -days 3650 -sha512
openssl pkcs12 -export -in "qm-client.crt" -name "qm-client" -certfile "ca.crt" -inkey "qm-client.key" -out "qm-client.p12" -passout pass:PASSWORD
cat qm-client.crt ca.crt > qm-client-chain.crt

oc delete cm queuemanager-configmap
oc apply  -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: queuemanager-configmap
data:
  queuemanager.mqsc: |
    DEFINE CHANNEL('MTLS.SVRCONN') CHLTYPE(SVRCONN) SSLCAUTH(REQUIRED) SSLCIPH('ANY_TLS13_OR_HIGHER') REPLACE
    SET CHLAUTH('MTLS.SVRCONN') TYPE(SSLPEERMAP) SSLPEER('CN=*') USERSRC(NOACCESS) ACTION(REPLACE)
    SET CHLAUTH('MTLS.SVRCONN') TYPE(SSLPEERMAP) SSLPEER('CN=qm-client') USERSRC(MAP) MCAUSER('app1') ACTION(REPLACE)
    SET AUTHREC PRINCIPAL('app1') OBJTYPE(QMGR) AUTHADD(CONNECT,INQ)
    DEFINE QLOCAL('EXAMPLE.QUEUE') REPLACE
    SET AUTHREC PROFILE('EXAMPLE.QUEUE') PRINCIPAL('app1') OBJTYPE(QUEUE) AUTHADD(BROWSE,PUT,GET,INQ)
  queuemanager.ini: |
    Service:
        Name=AuthorizationService
        EntryPoints=14
        SecurityPolicy=UserExternal
EOF


oc delete QueueManager queuemanager-1
sleep 5
oc create -f - << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: queuemanager-1
spec:
  license:
    accept: true  
    license: L-QYVA-B365MB
    use: Production
  queueManager:
    name: EXAMPLEQM
    mqsc:
    - configMap:
        name: queuemanager-configmap
        items:
        - queuemanager.mqsc
    ini:
    - configMap:
        name: queuemanager-configmap
        items:
        - queuemanager.ini
    storage:
      queueManager:
        type: ephemeral
  version: 9.4.1.1-r1
  web:
    enabled: true
  pki:
    keys:
      - name: default
        secret:
          secretName: queuemanager
          items:
            - tls.key
            - tls.crt
            - ca.crt
EOF
while true; do
        HOSTNAME=$(oc get route queuemanager-1-ibm-mq-qm --template="{{.spec.host}}")
        if [[ $? -ne 0 ]]; then 
               sleep 5
        else
                break
        fi
done
echo $HOSTNAME

cat << EOF > ccdt.json
{
    "channel":
    [
        {
            "name": "MTLS.SVRCONN",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$HOSTNAME",
                        "port": 443
                    }
                ],
                "queueManager": "EXAMPLEQM"
            },
            "transmissionSecurity":
            {
              "cipherSpecification": "ANY_TLS13",
              "certificateLabel": "qm-client"
            },
            "type": "clientConnection"
        }
   ]
}
EOF


cat << EOF > mqclient.ini 
Channels:
  ChannelDefinitionDirectory=.
  ChannelDefinitionFile=ccdt.json
SSL:
  OutboundSNI=HOSTNAME
  SSLKeyRepository=qm-client.p12
  SSLKeyRepositoryPassword=PASSWORD 
EOF


echo NOW RUN:
echo -e export MQSSLTRUSTSTORE=qm-client-chain.crt\\n/opt/mqm/samp/bin/amqsputc EXAMPLE.QUEUE EXAMPLEQM
popd

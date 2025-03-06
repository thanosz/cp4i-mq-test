# cp4i-mq-test
If you need a Red Hat® OpenShift® Route to connect an application to an IBM® MQ queue manager from outside a Red Hat OpenShift cluster, you must enable TLS on IBM MQ queue manager and client application, because the Red Hat OpenShift Container Platform Router uses SNI for routing requests to the IBM MQ queue manager. SNI is only available in the TLS protocol when a TLS 1.2 or higher protocol is used. 

This is a simple script to create a TLS-enabled Queue Manager. It creates all necessary certificates and configuration for both QM and MQ Client.

To test you need an MQ Client. This script produces the configuration needed to run ```amqsputc``` which is installed with IBM MQ redistributable client (windows/linux: [https://ibm.biz/mq94redistclients](), macos: [https://developer.ibm.com/tutorials/mq-macos-dev/]())

# Usage
* clone the repository to a linux machine
* make sure openssl is installed
* login to OCP with oc
* change to a progect where your QM will be deployed
* run the script
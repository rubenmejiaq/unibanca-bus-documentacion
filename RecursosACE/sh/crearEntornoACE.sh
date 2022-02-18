# Editar los siguientes 2 parámetros
NODE=UBA1D
QM=QMUBA1D
FXPIB=12.0.3.0
LST_IS_HTTPS=(IS_INST1_01,8005 IS_INST2_01,8010)
LST_IS_HTTP=(IS_INST1_01,7005 IS_INST2_01,7010)
PATH_JKS=/apps/bus/jks/
ADMIN_PORT=4414
PASSWORD=Un1banca
ALIASKEY=UnibancaSelfsigned
##############################################

echo  -e "\n\n  ****    Creacion de nuevo ambiente ACE para UNIBANCA    ****    \n\n"

# Crea el QM local del Bus
crtmqm -c "QM del nodo ${NODE}" -u SYSTEM.DEAD.LETTER.QUEUE -h 256 -lc -lp 20 -ls 15  ${QM}
strmqm ${QM}

echo  -e "\n ......Queue manager ${QM} creado \n"

# Crea el Integration Node con seguridad administrativa activa
mqsicreatebroker ${NODE} -q ${QM} 
mqsistart ${NODE}
mqsichangeproperties  --integration-node  ${NODE}  -n defaultQueueManager  -v ${QM}
mqsichangeproperties  --integration-node  ${NODE}  -n version -v ${FXPIB}
echo -e "\n ......Integration Node ${NODE} creado \n"


jks=${PATH_JKS}${NODE}.jks
if ! [ -f "$jks" ]; then
	# Crea el Almacen de llaves del Integration Node
	echo -e ${PASSWORD} | keytool -genkey -keyalg RSA -alias ${ALIASKEY} -keystore ${PATH_JKS}${NODE}.jks  -dname "CN=Unibanca,O=UBA,OU=Unibanca,L=Lima,C=PE" -storepass ${PASSWORD} -keypass ${PASSWORD} -validity 360 -keysize 2048
	echo -e ${PASSWORD} | keytool -export -alias  ${ALIASKEY} -file  ${PATH_JKS}${ALIASKEY}.der -keystore  ${PATH_JKS}${NODE}.jks -storepass ${PASSWORD}
	openssl x509 -inform der -in  ${PATH_JKS}${ALIASKEY}.der -out  ${PATH_JKS}${ALIASKEY}.pem
	echo -e ${PASSWORD} | keytool -importkeystore -srckeystore  ${PATH_JKS}${NODE}.jks -destkeystore ${PATH_JKS}keystore.p12 -deststoretype PKCS12 -storepass ${PASSWORD} -keypass ${PASSWORD}
	openssl pkcs12 -in ${PATH_JKS}keystore.p12  -nodes -nocerts -out  ${PATH_JKS}${ALIASKEY}.key   -password pass:${PASSWORD}
	echo  -e "\n ......Almacen de llaves creado ${jks} \n"
else
	echo  -e "\n ......Utilizando almacen existente ${jks}  \n"
fi


mqsicreateexecutiongroup ${NODE} -e IS_CORE_01
echo -e "\n ......Integration Server Core Creado \n"

# Activa el SSL a nivel de Integration Node.
#Configuracion del Admin security  ----->
mqsisetdbparms ${NODE} -n brokerKeystore::password -u ignore -p ${PASSWORD}
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n authorizationEnabled -v true
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n authorizationMode -v file
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n basicAuth -v true
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n minimumTlsVersion -v TLSv1.2
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n port -v ${ADMIN_PORT}
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n sslCertificate -v ${PATH_JKS}${ALIASKEY}.pem
mqsichangeproperties --integration-node ${NODE} -b RestAdminListener -n sslPassword -v ${PATH_JKS}${ALIASKEY}.key


echo -e "\n......Configuracion de seguridad del nodo creado \n"

mqsistop ${NODE}
mqsistart ${NODE}

echo -e "\n......Creacion de Integration Server con HTTPS:\n"
# Creacion de los integration server con el puerto HTTPS
for SERVER in ${LST_IS_HTTPS[@]}
do
  myarray=$(echo $SERVER | tr "," "\n")
  PORT_SRV=(${myarray})
  IS=${PORT_SRV[0]}
  PORT_HTTPS=${PORT_SRV[1]}
  mqsicreateexecutiongroup ${NODE} -e ${IS} -w 600
  mqsichangeproperties ${NODE} -e ${IS} -o ComIbmJVMManager -n keystoreFile -v ${PATH_JKS}${NODE}.jks
  mqsichangeproperties ${NODE} -e ${IS} -o ComIbmJVMManager -n keystorePass -v brokerKeystore::password
  mqsichangeproperties ${NODE} -e ${IS} -o ComIbmJVMManager -n truststoreFile -v ${PATH_JKS}${NODE}.jks
  mqsichangeproperties ${NODE} -e ${IS} -o ComIbmJVMManager -n truststorePass -v brokerKeystore::password
  mqsichangeproperties ${NODE} -e ${IS} -o HTTPSConnector -n port,explicitlySetPortNumber -v ${PORT_HTTPS},${PORT_HTTPS}
  mqsichangeproperties ${NODE} -e ${IS} -o HTTPSConnector -n ReqClientAuth -v false
  mqsichangeproperties ${NODE} -e ${IS} -o HTTPSConnector -n TLSProtocols -v TLSv1.2
  mqsichangeproperties ${NODE} -e ${IS} -o ExecutionGroup -n soapNodesUseEmbeddedListener -v true
  
  echo "-->${IS} ${PORT_HTTPS} "
done


echo -e "\n......Asignacion de puertos HTTP:\n"
# Asignacion del puerto HTTP por Integration Server
for SERVER in ${LST_IS_HTTP[@]}
do
  myarray=$(echo $SERVER | tr "," "\n")
  PORT_SRV=(${myarray})
  IS=${PORT_SRV[0]}
  PORT_HTTP=${PORT_SRV[1]}
  #Configurar propiedades del HTTPSConnector
  mqsichangeproperties ${NODE} -e ${IS} -o HTTPConnector -n explicitlySetPortNumber -v ${PORT_HTTP} 
  mqsichangeproperties ${NODE} -e ${IS} -o ExecutionGroup -n httpNodesUseEmbeddedListener -v true
  echo -e "\n-->${IS} ${PORT_HTTP} \n"  
done

# Crear perfiles de autorizacion:

mqsichangefileauth ${NODE} -r gr_devs -p read+,execute+,write-
mqsichangefileauth ${NODE} -r gr_admin -p all+ 

# Crear usuarios de logueo a la web administrativa:

mqsiwebuseradmin ${NODE} -c -u ibdeveloper -a ibdeveloper1 -r gr_devs
mqsiwebuseradmin ${NODE} -c -u ibadmin -a ibadmin1 -r gr_admin 

# Asignar permisos por integration server core
mqsichangefileauth ${NODE} -e IS_CORE_01 -r gr_admin -p all+ 
mqsichangefileauth ${NODE} -r gr_admin -o Data -p all+ 
mqsichangefileauth ${NODE} -r gr_devs -o Data -p all+ 

echo -e "\n......Asignacion de permisos a los integration servers:\n"
# Asignar permisos por Integration server de servicio
for SERVER in ${LST_IS_HTTP[@]}
do
  myarray=$(echo $SERVER | tr "," "\n")

  PORT_SRV=(${myarray})
  IS=${PORT_SRV[0]}
  mqsichangefileauth ${NODE} -e ${IS} -r gr_devs -p read+,write+
  mqsichangefileauth ${NODE} -e ${IS} -r gr_admin -p all+ 
  mqsichangefileauth ${NODE} -e ${IS} -r gr_admin -o Data -p all+ 
  mqsichangefileauth ${NODE} -e ${IS} -r gr_devs -o Data -p all+ 

  echo "-->${IS} "
done

mqsistop ${NODE}
mqsistart ${NODE}


echo -e "\n......Configuracion de grupos creada \n"

echo -e "\n......Objetos creados: \n"

mqsilist
mqsilist ${NODE}
dspmq -m ${QM}
dspmqinf ${QM}

echo -e "\n......Entorno del Bus creado! \n"





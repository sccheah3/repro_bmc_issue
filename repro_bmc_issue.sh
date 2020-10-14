#! /bin/bash

UNIQ_PASS="ABCDEFGH"
BMC_IP="123.123.123.123"
PDU_IP="234.234.234.234"
PDU_PORTS=(5 6)
CYCLE_LOG_FILE="cycles.log"

TRIPP_SNMP_PORT=161

PORT_ON()
{
	# ServerTech/APC
	# snmpset -v2c -c private $1 1.3.6.1.4.1.1718.3.2.3.1.11.1.1.$2 integer 1 &> /dev/null
	snmpset -v 2c -c tripplite $1:$TRIPP_SNMP_PORT .1.3.6.1.4.1.850.100.1.10.2.1.4.$2 integer 0 &> /dev/null
}

PORT_OFF()
{
	# ServerTech/APC
	# snmpset -v2c -c private $1 1.3.6.1.4.1.1718.3.2.3.1.11.1.1.$2 integer 2 &> /dev/null
	snmpset -v 2c -c tripplite $1:$TRIPP_SNMP_PORT .1.3.6.1.4.1.850.100.1.10.2.1.4.$2 integer 1 &> /dev/null
}

AC_OFF()
{
	ping -c 1 $BMC_IP
	while [ $? -eq 0 ] ; do
		for p in $PDU_PORTS ; do
			PORT_OFF $PDU_IP $p
		done
		sleep 5
		ping -c 1 $BMC_IP
	done
}

AC_ON()
{
	ATTEMPTS=0
	ping -c 1 $BMC_IP
	while [ $? -ne 0 ] ; do
		if [ "$ATTEMPTS" -ge 1800 ] ; then
			echo "FAIL: unable to ping BMC.\n"
			exit 1
		fi

		for p in $PDU_PORTS ; do
			PORT_ON $PDU_IP $p
		done
		sleep 1
		ATTEMPTS=$(( $ATTEMPTS + 1 ))
		ping -c 1 $BMC_IP
	done
}

AC_CYCLE()
{
	AC_OFF
	sleep 30
	AC_ON
}


while true ; do

	# change BMC password to ADMIN:ADMIN
	ipmitool -U ADMIN -P ADMIN -H $BMC_IP sdr
	while [ $? -ne 0 ] ; do
		ipmitool -U ADMIN -P $UNIQ_PASS -H $BMC_IP raw 0x0 0x0 0x0 # removed original raw command
		sleep 90
		ipmitool -U ADMIN -P ADMIN -H $BMC_IP sdr
	done

	AC_CYCLE

	# sanity check after ac cycle
	ipmitool -U ADMIN -P ADMIN -H $BMC_IP mc info
	if [ $? -ne 0 ] ; then
		echo "FAIL: unable to read mc info.\n"
		exit 2
	fi

	# change back to unique pass
	ipmitool -U ADMIN -P ADMIN -H $BMC_IP raw 0x0 0x0 # removed original raw command
	sleep 60

	# attempt to read mc info w/ uniq pass 100 times
	ATTEMPTS=0
	ipmitool -U ADMIN -P $UNIQ_PASS -H $BMC_IP mc info
	while [ $? -ne 0 ] ; do
		if [ $ATTEMPTS -ge 100 ] ; then 
			echo "FAIL: unable to read mc info.\n"
			exit 3
		fi

		sleep 1
		ATTEMPTS=$(( $ATTEMPTS + 1 ))
		ipmitool -U ADMIN -P $UNIQ_PASS -H $BMC_IP mc info
	done

	AC_CYCLE

	# sanity check after ac cycle for uniq pass
	ipmitool -U ADMIN -P $UNIQ_PASS -H $BMC_IP mc info
	if [ $? -ne 0 ] ; then
		echo "FAIL: unable to read mc info.\n"
		exit 5
	fi

	if [[ ! -f "$CYCLE_LOG_FILE" ]] ; then
		echo "0: $( date )" > $CYCLE_LOG_FILE
	else
		echo "$( cat $CYCLE_LOG_FILE | wc -l ): $( date )" >> $CYCLE_LOG_FILE
	fi
done
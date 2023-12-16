#!/bin/bash -ex

while [[ $# -gt 0 ]]
do
i="$1"

case $i in
    -h)
    shift
    HOST_NAME=$1
    shift
    ;;
    -s)
    shift
    PRIV_SUBNET=$1
    shift
    ;;
    -j)
    shift
    JOB_ID=$1
    shift
    ;;
    -i)
    shift
    PRIV_IP=$1
    shift
    ;;
    -m)
    MASTER=true
    shift
    ;;
    *)
    shift
    ;;
esac
done


GATEWAY_IP=$(ip -4 addr show $(ip -4 route list 0/0 | awk -F' ' '{ print $5 }') | grep -oP "(?<=inet\\s)\\d+(\\.\\d+){3}")

echo "----------------------------------------------------"
echo $(date) ": start openstack initialization (HOST: ${HOST_NAME}, IP=$GATEWAY_IP, master: ${MASTER})"

hostname ${HOST_NAME}.openworkload.org
echo ${HOST_NAME}.openworkload.org > /etc/hostname
echo $(date) ": hostname=$(hostname)"

echo $GATEWAY_IP ${HOST_NAME}.openworkload.org ${HOST_NAME} >> /etc/hosts
echo $(date) ": /etc/hosts:"
cat /etc/hosts
echo


# FIXME: re-configure openstack to get rid of this domain
sed -i -n "/openstacklocal/!p" /etc/resolv.conf
echo $(date) ": /etc/resolv.conf:"
cat /etc/resolv.conf
echo

# Fix docker connections failures
# https://github.com/systemd/systemd/issues/3374
sed -i s/MACAddressPolicy=persistent/MACAddressPolicy=none/g /lib/systemd/network/99-default.link
echo $(date) ": 99-default.link:"
cat /lib/systemd/network/99-default.link
echo

if [ $MASTER == "true" ];
then
    echo "/home ${PRIV_SUBNET}(rw,async,no_root_squash)" | sed "s/\\/25/\\/255.255.255.0/g" >> /etc/exports
    echo $(date) ": /etc/exports:"
    cat /etc/exports
    echo

    # Temporary disable for debug purposes
    #systemctl enable nfs-kernel-server
    #systemctl restart nfs-kernel-server
    #echo $(date) ": systemctl | grep nfs:"
    #systemctl | grep nfs

    mkdir /var/swm
    echo "host:/opt/swm /var/swm nfs rsize=32768,wsize=32768,hard,intr,async 0 0" >> /etc/fstab

else
    echo "${PRIV_IP}:/home /home nfs rsize=32768,wsize=32768,hard,intr,async 0 0" >> /etc/fstab
    echo $(date) ": /etc/fstab:"
    cat /etc/fstab
    echo

    echo $(date) ": waiting for mount ..."
    until mount -a || (( count++ >= 20 )); do sleep 5; done
    echo $(date) ": mounted."

    systemctl restart docker # fix rare "connection closed" issues

fi
echo

echo SWM_SNAME=${HOST_NAME} > /etc/swm.conf
echo $(date) ": /etc/swm.conf:"
cat /etc/swm.conf
echo

JOB_DIR=/opt/swm/spool/job/$JOB_ID
echo $(date) ": create job directory: $JOB_DIR"
mkdir -p $JOB_DIR

systemctl enable swm
systemctl start swm

echo $(date) ": systemctl | grep swm:"
systemctl | grep swm

echo $(date) ": ps aux | grep swm:"
ps aux | grep swm

echo
echo $(date) ": the initialization has finished"
echo "----------------------------------------------------"
exit 0

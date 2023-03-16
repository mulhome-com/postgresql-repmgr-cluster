#/bin/bash

scriptname="$(basename $0)"
currentpath="$(cd -- "$(dirname "$0")" > /dev/null 2>&1; pwd -P)"

print_usage() {
	printf "USAGE:\n %s [OPTIONS]\n\n" "${scriptname}" >&2
	printf "options:\n" >&2
	printf " -h, --help          Print the usage for this shell.\n" >&2
	printf " -i, --ip            The ip address for communication between master and slave.\n" >&2
	printf " -m, --mask          The mask value for that ip address.\n" >&2
	printf " -M, --master        The ip address for master server.\n" >&2
	printf " -s, --selfip        The ip address for self host.\n" >&2
	printf " -t, --target        The target one which to operate, just like master or slave.\n" >&2
	printf " -v, --version       The version of target postgresql server, default 12.\n" >&2
	printf "" >&2
	exit 0
}

TARGETS=( master slave )
TARGET=slave

IPADDR=""
IPMASK=""

MASTER=""

NODEID=2
SELFIP=""
VERSION=12

while [ "$#" -gt 0 ];
do
	case $1 in
		-i | --ip)
			shift;
			IPADDR=$1
			shift
			;;
		-m | --mask)
			shift;
			IPMASK=$1
			shift
			;;
		-M | --master)
			shift;
			MASTER=$1
			shift
			;;
		-s | --selfip)
			shift;
			SELFIP=$1
			shift
			;;
		-t | --target)
			shift;
			TARGET=$1
			shift
			;;
		-v | --version)
			shift;
			VERSION=$1
			shift
			;;
		-h | --help)
			print_usage
			;;
	esac
done

if [[ ! " ${TARGETS[@]} " =~ " ${TARGET} " ]]; then
	printf "Error:\n The target (${TARGET}) is not correct.\n" >&2
	print_usage
fi

if [[ -z "${IPADDR}" ]]; then
	printf "Error:\n The ip address cannot be empty.\n" >&2
	print_usage
fi

if [[ -z "${IPMASK}" ]]; then
	printf "Error:\n The ip mask cannot be empty.\n" >&2
	print_usage
fi

if [[ -z "${MASTER}" ]]; then
	printf "Error:\n The ip for master cannot be empty.\n" >&2
	print_usage
fi

if [[ -z "${SELFIP}" ]]; then
	printf "Error:\n The ip for self cannot be empty.\n" >&2
	print_usage
fi


log_info() {
	msg=$1
	sleep 1
	echo "INFO: ${msg}"
}

echo_msg() {
	msg=$1
	file=$2
	sudo bash -c "echo \"${msg}\" >> ${file}"
}

install_operate() {

	log_info "Postgresql server has been installed ..."
	server_exist=$(dpkg --list | grep ^ii | grep postgresql-${VERSION})
	if [[ -z "${server_exist}" ]]; then
		sudo apt install postgresql-${VERSION} -y
	fi

	log_info "Postgresql repmgr has been installed ..."
	repmgr_exist=$(dpkg --list | grep ^ii | grep postgresql-${VERSION}-repmgr)
	if [[ -z "${repmgr_exist}" ]]; then
		sudo apt install postgresql-${VERSION}-repmgr -y
	fi
}

master_operate() {

	install_operate

	log_info "Make user postgres login without password ..."
	pg_path=$(sudo find /etc/postgresql/ -name pg_hba.conf | grep ${VERSION})
	sudo cp -f conf/pg_hba.conf ${pg_path}
	sudo sed -i -e 's/peer/trust/g' ${pg_path}
	sudo systemctl restart postgresql

	log_info "Create the user repmgr for relication ..."
	psql -U postgres -c "drop user if exists repmgr;"
	psql -U postgres -c "drop database if exists repmgr;"
	psql -U postgres -c "create user repmgr;"
	psql -U postgres -c "alter role repmgr superuser;"
	psql -U postgres -c "create database repmgr with owner repmgr;"
	psql -U postgres -c "alter role postgres with password 'IKge6geoZHio';"

	echo_msg "host    replication    repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    repmgr         repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    all            all           0.0.0.0/0        md5" ${pg_path}

	log_info "Create the postgresql configure ..."
	cnf_path=$(sudo find /etc/postgresql/ -name postgresql.conf | grep ${VERSION})
	sudo cp -f conf/postgresql.conf ${cnf_path}
	sudo sed -i -e "s/VERSION/${VERSION}/g" ${cnf_path}

	echo_msg "listen_addresses = '*'"  ${cnf_path}
	echo_msg "max_wal_senders = 10" ${cnf_path}
	echo_msg "max_replication_slots = 10" ${cnf_path}
	echo_msg "wal_level = 'hot_standby'" ${cnf_path}
	echo_msg "hot_standby = on" ${cnf_path}
	echo_msg "archive_mode = on" ${cnf_path}
	echo_msg "archive_command = '/bin/true'" ${cnf_path}
	echo_msg "shared_preload_libraries = 'repmgr'" ${cnf_path}

	sudo systemctl restart postgresql@${VERSION}-main
	sleep 1

	CONF=/etc/postgresql/${VERSION}/main/repmgr.conf
	sudo rm -rf ${CONF} > /dev/null 2>&1

	sudo cp repmgr.conf.d/master.conf ${CONF} 
	sudo sed -i -e "s/VERSION/${VERSION}/g" ${CONF}
	sudo sed -i -e "s/HOST/${MASTER}/g" ${CONF}

	log_info "Register master by repmgr command ..."
	sudo runuser -l postgres -c "repmgr -f ${CONF} primary register"
	sleep 1
	log_info "Check master status by repmgr command ..."
	sudo runuser -l postgres -c "repmgr -f ${CONF} cluster show"
	sleep 1
	log_info "Done"
}

slave_operate() {

	install_operate

	log_info "Make user postgres login without password ..."
	pg_path=$(sudo find /etc/postgresql/ -name pg_hba.conf)
	sudo cp -f conf/pg_hba.conf ${pg_path}
	sudo sed -i -e 's/peer/trust/g' ${pg_path}

	echo_msg "host    replication    repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    repmgr         repmgr        ${IPADDR}/${IPMASK}    trust" ${pg_path}
	echo_msg "host    all            all           0.0.0.0/0        md5" ${pg_path}
	sudo systemctl restart postgresql@${VERSION}-main

	log_info "Create the postgresql configure ..."
	cnf_path=$(sudo find /etc/postgresql/ -name postgresql.conf)
	sudo cp -f conf/postgresql.conf ${cnf_path}
	sudo sed -i -e "s/VERSION/${VERSION}/g" ${cnf_path}
	echo_msg "listen_addresses = '*'"  ${cnf_path}
	sudo systemctl stop postgresql@${VERSION}-main
	sleep 1

	CONF=/etc/postgresql/${VERSION}/main/repmgr.conf
	sudo rm -rf ${CONF} > /dev/null 2>&1

	sudo cp repmgr.conf.d/standby.conf ${CONF} 
	sudo sed -i -e "s/VERSION/${VERSION}/g" ${CONF}
	sudo sed -i -e "s/NUMBER/${NODEID}/g" ${CONF}
	sudo sed -i -e "s/HOST/${SELFIP}/g" ${CONF}

	sudo runuser -l postgres -c "repmgr -h ${MASTER} -U repmgr -d repmgr -f ${CONF} standby clone --dry-run"
	sleep 1
	log_info "Build standby by repmgr command ..."
	sudo rm -rf /var/lib/postgresql/${VERSION}/main
	sudo runuser -l postgres -c "repmgr -h ${MASTER} -U repmgr -d repmgr -f ${CONF} standby clone"
	sleep 1
	sudo systemctl start postgresql@${VERSION}-main
	sleep 1
	log_info "Register standby by repmgr command ..."
	sudo runuser -l postgres -c "repmgr -f ${CONF} standby register"
	sleep 1
	log_info "Check standby status by repmgr command ..."
	sudo runuser -l postgres -c "repmgr -f ${CONF} cluster show"
	sleep 1
	log_info "Done"
}

if [[ "${TARGET}" == "master" ]]; then
	master_operate
elif [[ "${TARGET}" == "slave" ]]; then
	slave_operate
fi

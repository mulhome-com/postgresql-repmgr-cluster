# postgresql-repmgr-cluster
Build the postgresql cluster by repmgr tool in the multiple hosts.

About postgresql + repmgr 

repmgr (Replication Manager) is an open source tool used for managing the replication and failover of PostgreSQL clusters. In this post we will learn to set up and configure the cluster for automatic failover. 


Primary server:

> bash build.sh -i 10.11.12.0 -m 24 -t master -s 10.11.12.200 -M 10.11.12.200 -v 12

Run the above command in one host.

- "10.11.12.0" is the current network.
- "24" is the mask of this current network.
- "master" is the target role of this host.
- "10.11.12.200" is the ip address of this host.
- "10.11.12.200" is the ip address of master host.
- "12" is the version of postgresql server.


Standby server:

> bash build.sh -i 10.11.12.0 -m 24 -t slave -s 10.11.12.201 -M 10.11.12.200 -v 12

Run the above command in one host.

- "10.11.12.0" is the current network.
- "24" is the mask of this current network.
- "slave" is the target role of this host.
- "10.11.12.201" is the ip address of this host.
- "10.11.12.200" is the ip address of master host.
- "12" is the version of postgresql server.


Test:

Login the primary server

> create table test (id int);


Then log into the standby server

> \dt 

and then

> \d+ test


Note:

It seems that this tool does only work for postgresql 12 server.

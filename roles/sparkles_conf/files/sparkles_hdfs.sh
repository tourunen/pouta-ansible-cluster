sudo -u hdfs hadoop fs -mkdir /user/cloud-user
sudo -u hdfs hadoop fs -chown -R cloud-user /user/cloud-user
sudo -u hdfs hadoop fs -mkdir -p /sparkles/tmp
sudo -u hdfs hadoop fs -mkdir -p /sparkles/hdf5
sudo -u hdfs hadoop fs -mkdir -p /sparkles/files
sudo -u hdfs hadoop fs -mkdir -p /sparkles/features
sudo -u hdfs hadoop fs -mkdir -p /sparkles/modules
sudo -u hdfs hadoop fs -chown -R cloud-user /sparkles

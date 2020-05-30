---
title: Hadoop集群搭建
categories:
  - BigData
tags:
  - hadoop
  - hdfs
  - yarn
  - mapreduce
  - spark
  - flink
date: 2020-05-28 14:15:05
---

## Hadoop集群搭建

### 虚拟机准备

1. 安装[Visual Box](https://download.virtualbox.org/virtualbox/6.1.8/VirtualBox-6.1.8-137981-Win.exe)
2. 准备[CentOS 7镜像文件](http://isoredirect.centos.org/centos/7/isos/x86_64/)
3. [创建虚拟机](https://jingyan.baidu.com/article/4dc4084868a1e4c8d946f133.html)
4. [设置虚拟机固定IP](https://www.linuxidc.com/Linux/2018-04/151924.htm)

<!-- more -->

    ```bash
    vim /etc/sysconfig/network-scripts/ifcfg-enp0s3

    # ----------
    BOOTPROTO="static"
    IPADDR="192.168.56.101"
    ```

5. 设置虚拟机主机名

    ```bash
    vim /etc/sysconfig/network

    # ----------
    NETWORKING=yes
    HOSTNAME=linux101
    ```

6. 设置虚拟机域名映射

    ```bash
    vim /etc/hosts

    # ----------
    192.168.56.101 linux101
    ```

7. 复制虚拟机：设置名称，选择为所有网卡重新生成MAC地址，完全复制
8. 按上述1~6配置准备linux102、linux103虚拟机
9. 配置Windows本机域名映射

    > 便于之后访问集群Web UI

    ```bash
    code C:\Windows\System32\drivers\etc\hosts

    # ----------
    192.168.56.101 linux101
    192.168.56.102 linux102
    192.168.56.103 linux103
    ```

### 前置工作

1. 创建hadoop用户

    ```bash
    sudo useradd -m hadoop -s /bin/bash
    ```

2. 修改hadoop用户密码

    ```bash
    sudo passwd hadoop
    ```

3. 设置hadoop用户组

    ```bash
    sudo usermod -a -G hadoop hadoop
    ```

4. 为hadoop用户增加管理员权限

    ```bash
    sudo vim sudoers

    # ----------
    hadoop ALL=(ALL) ALL
    ```

5. 设置机器免密登录

    > 便于在集群间执行管理脚本

    ```bash
    ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa # 生成rsa密钥
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys # 加入授权
    chmod 0600 ~/.ssh/authorized_keys
    ```

    ```bash
    ssh hadoop@linux101 # 测试免密登录
    ```

    仍需要密码登陆问题解决:

    ```bash
    sudo vim /etc/ssh/sshd_config

    # ----------
    PermitRootLogin yes # 禁用root账户登录

    StrictModes no # 是否让sshd去检查用户家目录或相关档案的权限数据

    PubkeyAuthentication yes # 是否允许用户自行使用成对的密钥系统进行登入行为
    AuthorizedKeysFile  .ssh/authorized_keys
    # ----------

    service sshd restart # 重启sshd服务
    ```

6. 关闭防火墙

    > 为了访问集群Web UI和集群各结点互联互通（eg: NameNode和DataNode, ...）

    ```bash
    systemctl stop firewalld.service   # 停止防火墙
    systemctl disable firewalld.service  # 禁止防火墙开机启动
    ```

7. 下载[jdk8](https://www.oracle.com/java/technologies/javase/javase-jdk8-downloads.html)并解压

    ```bash
    tar -zvxf jdk-8u251-linux-x64.tar.gz -C ~/module
    ```

8. 配置环境变量

    ```bash
    # 注意：这里由于虚拟机资源紧张我暂不使用hadoop用户
    sudo vim /etc/profile

    # ----------
    # JAVA
    export JAVA_HOME=/home/bob/module/jdk1.8.0_251
    export PATH=$PATH:$JAVA_HOME/bin
    # ----------

    source /etc/profile
    ```

9. 准备辅助脚本

  - 集群多节点互传差异文件
    ```bash
    #!/bin/bash

    # 获取输入参数个数，如果没有参数直接退出
    args_count=$#
    if ((args_count==0)); then
      echo no args;
      exit;
    fi

    # 获取待分发文件名称
    arg1=$1
    fname=`basename $arg1`
    echo fname=$fname

    # 获取上级目录到绝对路径
    pdir=`cd -P $(dirname $arg1); pwd`
    echo pdir=$pdir

    # 获取当前用户名称
    user=`whoami`

    # 开始分发
    for ((host=101; host<104; host++)); do
      echo --------------------linux$host--------------------
      rsync -rvl $pdir/$fname $user@linux$host:$pdir
    done
    ```

  - 查看集群各节点java进程

    ```bash
    #!/bin/bash

    # 获取当前用户名称
    user=`whoami`

    for ((host=101; host<104; host++)); do
      echo --------------------linux$host--------------------
      ssh $user@linux$host "$JAVA_HOME/bin/jps"
    done
    ```

### 集群配置

- 集群规划

    linux101 | linux102 | linux103
    ---------|----------|----------
    NameNode | SecondaryNameNode | -
    DataNode | DataNode | DataNode
    - | - | ResourceManager
    NodeManager | NodeManager | NodeManager
    - | JobHistoryServer | -

1. 下载[hadoop-3.2.1](https://www.apache.org/dyn/closer.cgi/hadoop/common/hadoop-3.2.1/hadoop-3.2.1.tar.gz)并解压

    ```bash
    tar -zvxf hadoop-3.2.1/hadoop-3.2.1.tar.gz -C ~/module
    ```

    设置环境变量:

    ```bash
    sudo vim /etc/profile

    # ----------
    # Hadoop
    export HADOOP_HOME=/home/bob/module/hadoop-3.2.1
    export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
    # ----------

    source /etc/profile
    ```

2. 配置`hadoop-env.sh`

    ```bash
    export JAVA_HOME=/home/bob/module/jdk1.8.0_251
    ```

3. [配置](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/core-default.xml)`core-site.xml`

    ```xml
    <configuration>
        <property>
            <name>fs.defaultFS</name>
            <value>hdfs://linux101:9000</value>
        </property>
        <property>
            <name>hadoop.tmp.dir</name>
            <value>file:///home/bob/module/hadoop-3.2.1/data/tmp</value>
        </property>
    </configuration>
    ```

4. [配置](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/hdfs-default.xml)`hdfs-site.xml`

    ```xml
    <configuration>
        <property>
            <name>dfs.replication</name>
            <value>3</value>
        </property>
        <property>
            <name>dfs.namenode.name.dir</name>
            <value>file:///home/bob/module/hadoop-3.2.1/data/dfs/name</value>
        </property>
        <property>
            <name>dfs.datanode.data.dir</name>
            <value>file:///home/bob/module/hadoop-3.2.1/data/dfs/data</value>
        </property>

        <property>
            <name>dfs.namenode.secondary.http-address</name>
            <value>linux102:9868</value>
        </property>
    </configuration>
    ```

5. [配置](https://hadoop.apache.org/docs/stable/hadoop-yarn/hadoop-yarn-common/yarn-default.xml)`yarn-site.xml`

    ```xml
    <configuration>
        <property>
            <name>yarn.resourcemanager.hostname</name>
            <value>linux103</value>
        </property>
        <property>
            <name>yarn.nodemanager.aux-services</name>
            <value>mapreduce_shuffle</value>
        </property>
        <property>
            <name>yarn.nodemanager.env-whitelist</name>
            <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
        </property>

        <property>
            <name>yarn.log-aggregation-enable</name>
            <value>true</value>
        </property>
        <property>
            <name>yarn.log-aggregation.retain-seconds</name>
            <value>7200</value>
        </property>
        <property>
            <name>yarn.log.server.url</name>
            <value>http://linux102:19888/jobhistory/logs</value>
        </property>
    </configuration>
    ```

6. [配置](https://hadoop.apache.org/docs/stable/hadoop-mapreduce-client/hadoop-mapreduce-client-core/mapred-default.xml)`mapred-site.xml`

    ```xml
    <configuration>
        <property>
            <name>mapreduce.framework.name</name>
            <value>yarn</value>
        </property>
        <property>
            <name>mapreduce.application.classpath</name>
            <value>$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
        </property>

        <property>
            <name>mapreduce.jobhistory.address</name>
            <value>linux102:10020</value>
        </property>
        <property>
            <name>mapreduce.jobhistory.webapp.address</name>
            <value>linux102:19888</value>
        </property>
    </configuration>
    ```

7. 配置`workers`工作节点

    > 供集群启动、停止等管理脚本使用（eg: start-dfs.sh, ...）

    ```
    linux101
    linux102
    linux103
    ```

8. 将配置好的hadoop目录分发给其他节点

    ```bash
    xsync ~/module/hadoop-3.2.1
    ```

### 集群启动

1. 格式化dfs文件系统

    ```bash
    hdfs namenode -format
    ```
    
    注意：若二次格式化，则需要先删除各节点之前的`data`和`logs`目录，再启动dfs。

2. 启动`NameNode`和`DataNode`守护进程

    ```bash
    start-dfs.sh
    ```

    `xjps`确认进程存活，访问NameNode Web UI：http://linux101:9870/

    测试：

    ```bash
    hdfs dfs -mkdir -p /user/bob/wc/input    # 创建wordcount输入文件夹
    hdfs dfs -put wc.iput /user/bob/wc/input # 将准备好的单词文件放入输入文件夹
    ```

3. 启动`ResourceManager`和`NodeManager`守护进程

    ```bash
    start-yarn.sh
    ```

    `xjps`确认进程存活，访问ResourceManager Web UI：http://linux103:8088/

4. 启动作业历史记录服务器

    ```bash
    mr-jobhistory-daemon.sh start historyserver
    ```

    `xjps`确认进程存活，访问HistoryServer Web UI：http://linux102:19888/

5. 运行MapReduce任务

    ```bash
    hadoop jar share/hadoop/mapreduce/hadoop-mapreduce-examples-3.2.1.jar wordcount /user/bob/wc/input /user/bob/wc/output # 执行wordcount

    hdfs dfs -cat output/p* # 查看运行结果
    ```

6. 停止集群

    ```bash
    stop-dfs.sh # linux101上执行
    stop-yarn.sh # linux103上执行
    mr-jobhistory-daemon.sh stop historyserver # linux102上执行
    ```

    > 注意：以上启动/停止均需在对应节点执行，eg: NameNode->linux101 JobHistory->linux102 ResourceManager->linux103 

##  Spark On Yarn

- 集群规划

    linux101 | linux102 | linux103
    ---------|----------|----------
    Master | - | -
    Worker | Worker | Worker
    - | HistoryServer | -

1. 下载[spark-2.4.5](https://www.apache.org/dyn/closer.lua/spark/spark-2.4.5/spark-2.4.5-bin-hadoop2.7.tgz)并解压

    ```bash
    tar -zvxf spark-2.4.5-bin-hadoop2.7.tgz -C ~/module
    mv spark-2.4.5-bin-hadoop2.7 spark-2.4.5
    ```

    设置环境变量:

    ```bash
    sudo vim /etc/profile

    # ----------
    # Spark
    export SPARK_HOME=/home/bob/module/spark-2.4.5
    #export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
    # ----------

    source /etc/profile
    ```

2. [配置](https://spark.apache.org/docs/2.4.5/running-on-yarn.html)`spark-env.sh`

    ```bash
    mv spark-env.sh.template spark-env.sh
    vim spark-env.sh

    # ----------
    HADOOP_CONF_DIR=/home/bob/module/hadoop-3.2.1/etc/hadoop
    SPARK_MASTER_HOST=linux101
    SPARK_MASTER_PORT=7077
    ```

3. 配置`slaves`

    ```bash
    mv slaves.template slaves
    vim slaves

    # ----------
    linux101
    linux102
    linux103
    ```

4. 将配置好的spark目录分发给其他节点

    ```bash
    xsync ~/module/spark-2.4.5
    ```

5. 启动spark集群

    ```bash
    sbin/start-all.sh
    ```

    `xjps`确认spark进程存活，访问Spark Web UI：http://linux101:19888/

6. 配置作业历史服务器

    > 便于在Hadoop Web UI中查看Spark Job History

    ```bash
    mv spark-default.conf.template spark-default.conf
    vim spark-default.conf

    # ----------
    spark.eventLog.enabled           true  # 记录事件日志
    spark.eventLog.dir               hdfs://linux101:9000/spark/jobhistory # 事件日志保存路径（需预先在hdfs创建）
    spark.eventLog.compress          true  # 压缩事件日志
    spark.yarn.historyServer.address linux102:18080 # Hadoop Web UI 'TarckingUI'指向的Spark HistoryServer的地址
    ```

    ```bash
    vim spark-env.sh

    # ----------
    # Spark HistoryServer的访问端口，HistoryServer显示的最大应用程序数量，HistoryServer日志存放目录
    SPARK_HISTORY_OPTS="-Dspark.history.ui.port=18080
    -Dspark.history.retainedApplications=3
    -Dspark.history.fs.logDirectory=hdfs://linux101:9000/spark/jobhistory" # 
    ```

    ```bash
    # 分发配置到其他节点
    xsync spark-default.conf
    xsync spark-env.sh
    ```

7. 启动作业历史服务器

    ```bash
    sbin/start-history-server.sh # 启动Spark HistoryServer
    ```

    `xjps`确认进程存活

8. 执行测试

    ```bash
    bin/spark-submit --class org.apache.spark.examples.SparkPi \
        --master yarn \
        --deploy-mode cluster \
        --driver-memory 2g \
        --executor-memory 1g \
        --executor-cores 1 \
        examples/jars/spark-examples*.jar \
        10
    ```

##  Flink On Yarn

1. 下载[flink-1.9.3](https://www.apache.org/dyn/closer.lua/flink/flink-1.9.3/flink-1.9.3-bin-scala_2.12.tgz)并解压

    ```bash
    tar -zvxf flink-1.9.3-bin-scala_2.12.tgz -C ~/module
    mv flink-1.9.3-bin-scala_2.12 flink-1.9.3
    ```

    设置环境变量（可选）:

    ```bash
    sudo vim /etc/profile

    # ----------
    # Flink
    export FLINK_HOME=/home/bob/module/flink-1.9.3
    #export PATH=$PATH:$FLINK_HOME/bin
    # ----------

    source /etc/profile
    ```
    
2. 下载[hadoop](https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar)支持组件

    ```bash
    mv flink-shaded-hadoop-2-uber-2.8.3-10.0.jar ~/module/flink-1.9.3/lib
    ```

3. 配置`yarn-site.xml`

    > 提交应用程序的最大尝试次数

    ```xml
    <property>
        <name>yarn.resourcemanager.am.max-attempts</name>
        <value>4</value>
    </property>
    ```

4. [配置](https://ci.apache.org/projects/flink/flink-docs-release-1.9/zh/ops/jobmanager_high_availability.html)`flink-conf.yaml`

    ```bash
    vim conf/flink-conf.yaml

    # ----------
    high-availability: zookeeper
    high-availability.storageDir: hdfs:///linux101:9000/flink/ha/
    high-availability.zookeeper.quorum: linux101:2181,linux102:2181,linux103:2181
    high-availability.zookeeper.path.root: /flink
    ```

5. 配置ZooKeeper服务器

    ```bash
    vim conf/zoo.cfg

    # ----------
    server.1=linux101:2888:3888
    server.2=linux102:2888:3888
    server.3=linux103:2888:3888
    ```

6. 将配置好的flink目录分发给其他节点

    ```bash
    xsync ~/module/flink-1.9.3
    ```
    
7. 启动ZooKeeper仲裁

    ```bash
    ./bin/start-zookeeper-quorum.sh
    ```

8. 启动Flink Yarn Session

    - 分离模式

        ```bash
        ./bin/yarn-session.sh -n 3 -s 2 -nm flink-yarn-detach -d # 后台启动
        ./bin/flink run ./examples/batch/WordCount.jar # 运行任务
        ```

    - 客户端模式
    
        ```bash
        ./bin/flink run -m yarn-cluster -yn 3 -ys 2 -ynm flink-yarn-client ./examples/batch/WordCount.jar # 启动运行
        ```

9. 测试HA

    `xjps`查看YarnSessionClusterEntrypoint进程所在节点，到对应机器上kill掉该进程id

    访问 http://linux103:8088/ 点击查看`flink-yarn-detach`应用，会发现多出现一次appattempt，在Flink UI的JobManager选项卡下也可查看，再次提交flink job仍可运行。

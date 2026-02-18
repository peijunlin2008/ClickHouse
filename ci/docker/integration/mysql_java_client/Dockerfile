# docker build -t clickhouse/mysql-java-client .
# MySQL Java client docker container

FROM eclipse-temurin:21-jdk-alpine

RUN apk --no-cache add curl

ARG ver=9.2.0
RUN curl -L -o /mysql-connector-j-${ver}.jar https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${ver}/mysql-connector-j-${ver}.jar
ENV CLASSPATH=$CLASSPATH:/mysql-connector-j-${ver}.jar

WORKDIR /jdbc
COPY MySQLJavaClientTest.java MySQLJavaClientTest.java
RUN javac MySQLJavaClientTest.java

# docker build -t clickhouse/mysql-golang-client .
# MySQL golang client docker container

FROM golang:1.23-alpine

WORKDIR /opt

COPY ./main.go main.go

RUN go mod init none \
    && go get github.com/go-sql-driver/mysql@v1.8.1 \
    && go build main.go

# docker build -t clickhouse/mysql-golang-client .
# MySQL golang client docker container

FROM golang:1.24-alpine

RUN apk update && apk upgrade --no-cache

WORKDIR /opt

COPY ./main.go main.go

RUN go mod init none \
    && go get github.com/go-sql-driver/mysql@v1.8.1 \
    && go build main.go

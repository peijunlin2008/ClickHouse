# docker build -t clickhouse/mysql-golang-client .
# MySQL golang client docker container

FROM golang:1.24-alpine

RUN apk --no-cache upgrade

WORKDIR /opt

COPY ./main.go main.go

RUN go mod init none \
    && go get github.com/go-sql-driver/mysql@v1.6.0 \
    && go build main.go

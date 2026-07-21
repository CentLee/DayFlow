FROM golang:1.24.4-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/dayflow-api ./cmd/dayflow-api

FROM alpine:3.20

WORKDIR /app

RUN apk add --no-cache ca-certificates wget

COPY --from=builder /out/dayflow-api /usr/local/bin/dayflow-api
COPY migrations ./migrations

EXPOSE 8080

ENTRYPOINT ["dayflow-api"]

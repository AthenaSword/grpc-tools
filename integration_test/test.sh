#!/usr/bin/env bash
killall grpc-fixture
killall grpc-dump
set -e

testDir=$(dirname "${BASH_SOURCE}")
pushd "${testDir}"
certFile="_wildcard.github.io.pem"
keyFile="_wildcard.github.io-key.pem"

if [[ ! -f "$certFile" ]]; then
    echo "required file $certFile doesn't exist, generate it using \"mkcert *.github.io\""
    exit 1
fi
if [[ ! -f "$keyFile" ]]; then
    echo "required file $keyFile doesn't exist, generate it using \"mkcert *.github.io\""
    exit 1
fi

export GO111MODULE=on
go build github.com/bradleyjkemp/grpc-tools/grpc-fixture
go build github.com/bradleyjkemp/grpc-tools/grpc-dump
go build github.com/bradleyjkemp/grpc-tools/grpc-replay

# grpc-fixture serves mock RPCs
./grpc-fixture \
    --dump=test-golden.json \
    --port=16353 \
    --cert="${certFile}" \
    --key="${keyFile}" &
fixturePID=$!

# grpc-dump will dump the requests and responses to the fixture
HTTP_PROXY=localhost:16353 ./grpc-dump \
    --port=16354 \
    --cert="${certFile}" \
    --key="${keyFile}" > test-result.json &
dumpPID=$!

sleep 1 # wait for servers to start up

# grpc-replay makes request which are logged by grpc-dump and responded to by grpc-fixture
HTTP_PROXY=localhost:16354 ./grpc-replay \
    --dump=test-dump.json

# mimic a HTTP gRPC-Web requests
# Adapted from: https://stackoverflow.com/questions/52839792/how-do-i-map-my-working-curl-command-into-a-grpc-web-call
ALL_PROXY=localhost:16354 curl -X POST 'http://grpc-web.github.io/grpc.gateway.testing.EchoService/Echo' \
    -H 'Pragma: no-cache' -H 'X-User-Agent: grpc-web-javascript/0.1' -H 'Origin: http://localhost:8081' \
    -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: en-US,en;q=0.9' -H 'custom-header-1: value1' \
    -H 'User-Agent: Mozilla/5.0' -H 'Content-Type: application/grpc-web+proto' -H 'Accept: */*' \
    -H 'X-Grpc-Web: 1' -H 'Cache-Control: no-cache' -H 'Referer: http://localhost:8081/echotest.html' \
    -H 'Connection: keep-alive'

# And a HTTPS one for good measure
# Adapted from: https://stackoverflow.com/questions/52839792/how-do-i-map-my-working-curl-command-into-a-grpc-web-call
ALL_PROXY=localhost:16354 curl -X POST 'https://grpc-web.github.io:1234/grpc.gateway.testing.EchoService/Echo' \
    -H 'Pragma: no-cache' -H 'X-User-Agent: grpc-web-javascript/0.1' -H 'Origin: http://localhost:8081' \
    -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: en-US,en;q=0.9' -H 'custom-header-1: value1' \
    -H 'User-Agent: Mozilla/5.0' -H 'Content-Type: application/grpc-web+proto' -H 'Accept: */*' \
    -H 'X-Grpc-Web: 1' -H 'Cache-Control: no-cache' -H 'Referer: http://localhost:8081/echotest.html' \
    -H 'Connection: keep-alive'

kill ${fixturePID}
kill ${dumpPID}

wait

# Now check that the two results match
cmp test-result.json test-golden.json || (echo "Results are different"; exit 1)
echo "Test passes"

# Clean up
rm ./grpc-fixture
rm ./grpc-dump
rm ./grpc-replay
rm test-result.json
popd

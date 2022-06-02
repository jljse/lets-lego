#! /bin/bash

function usage() {
  echo "usage: $0 [-w WEBROOT] [-c CONTAINER] [-o OUTDIR] MAIL DOMAIN"
  echo "  Create SSL certificate by let's encrypt with lego."
  echo "  Results will be saved in OUTDIR directory."
  echo "  Use this script on the first time after you get new domain server and login to it."
  echo "  CAUTION: You have to clean port 80 before run this script."
  echo
  echo "  -c CONTAINER : Use already running nginx on container."
  echo "  -w WEBROOT : Specify nginx webroot."
  echo "  -o OUTDIR : Output directory (default: ./leg-output)"
  echo "  MAIL : Issuer's (Your) mail address"
  echo "  DOMAIN : Your domain name."
  echo
  echo "  (ex1) -c XXX -w /yyy => use nginx on container XXX, it's webroot is /yyy."
  echo "  (ex2)        -w /yyy => use nginx on host, it's webroot is /yyy."
  echo "  (ex3)                => use nginx on temporaly container."
}

OUTDIR=$(pwd)/lego-output

while getopts w:c:o: opt; do
  case "$opt" in
    w)
      WEBROOT=$OPTARG
      ;;
    c)
      CONTAINER=$OPTARG
      ;;
    o)
      OUTDIR=$OPTARG
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

MAIL=$1
DOMAIN=$2

if [ -z "$DOMAIN" ]; then
  usage
  exit 1
fi

# resolve relative path
mkdir -p $(dirname $OUTDIR)
OUTDIR=$(cd $(dirname $OUTDIR); pwd)/$(basename $OUTDIR)

tmpdir=$(mktemp -d)
trap "[ -f $tmpdir/this-is-tmpdir ] && rm -rf $tmpdir" EXIT

cd $tmpdir
touch this-is-tmpdir
wget https://github.com/go-acme/lego/releases/download/v4.3.1/lego_v4.3.1_linux_amd64.tar.gz
tar xzf lego_v4.3.1_linux_amd64.tar.gz

if [ -z "$CONTAINER" ] && [ -z "$WEBROOT" ]; then
  # run on temporary container
  docker run -d -p 80:80 --name temp-nginx nginx
  sleep 1
  docker cp ./lego temp-nginx:/root
  docker exec temp-nginx /root/lego \
    --email="$MAIL" --domains="$DOMAIN" \
    --path /root/.lego \
    --http --http.webroot /usr/share/nginx/html --accept-tos run
  docker cp temp-nginx:/root/.lego $OUTDIR
  docker stop temp-nginx
  docker rm temp-nginx
elif [ -n "$CONTAINER" ] && [ -n "$WEBROOT" ]; then
  # run on existing container
  docker cp ./lego $CONTAINER:/root
  docker exec $CONTAINER /root/lego \
    --email="$MAIL" --domains="$DOMAIN" \
    --path /root/.temp-lego \
    --http --http.webroot $WEBROOT --accept-tos run
  docker cp $CONTAINER:/root/.temp-lego $OUTDIR
  docker exec $CONTAINER rm -rf /root/lego /root/.temp-lego
elif [ -z "$CONTAINER"] && [ -n "$WEBROOT" ]; then
  # run on host
  ./lego \
    --email="$MAIL" --domains="$DOMAIN" \
    --path $OUTDIR \
    --http --http.webroot $WEBROOT --accept-tos run
else
  # error
  usage
  exit 1
fi

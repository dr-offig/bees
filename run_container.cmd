docker run --runtime=nvidia -it -p 127.0.0.1:8000:8000 -p 127.0.0.1:8087:8787 -e GROUPID=1001 -e PASSWORD=dunklebunt_lemming -e ROOT=true --mount src=ybotfs,dst=/home/bees/portal --hostname bees --name bees bees /bin/bash

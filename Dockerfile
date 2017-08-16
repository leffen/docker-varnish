# Varnish cache image for production

FROM alpine:3.5
LABEL MAINTAINER="Max Milton <max@wearegenki.com>"

ENV VARNISH_VERSION 4.1.5
ENV VARNISH_SHA256 b52d4d05dd3c571c5538f2d821b237ec029691aebbc35918311ede256404feb3

RUN set -xe \
	&& mkdir -p /usr/src \
	&& addgroup -g 3333 -S varnish \
	&& adduser -D -u 3333 -S -h /var/lib/varnish -s /sbin/nologin -G varnish varnish \
	&& apk add --no-cache --virtual .build-deps \
		curl \
		g++ \
		libedit-dev \
		linux-headers \
		make \
		ncurses-dev \
		pcre-dev \
		py-docutils \
	&& apk add --no-cache --virtual .varnish-deps \
		gcc \
		libc-dev \
		libedit \
		libgcc \
		pcre \
	&& cd /usr/src \
	&& curl -fSL https://repo.varnish-cache.org/source/varnish-$VARNISH_VERSION.tar.gz -o varnish.tar.gz \
	&& PATCH_URL_BASE=http://git.alpinelinux.org/cgit/aports/plain/main/varnish \
	&& curl -fSL $PATCH_URL_BASE/fix-compat-execinfo.patch -o fix-compat-execinfo.patch \
	&& curl -fSL $PATCH_URL_BASE/fix-stack-overflow.patch -o fix-stack-overflow.patch \
	&& curl -fSL $PATCH_URL_BASE/musl-mode_t.patch -o musl-mode_t.patch \
	&& curl -fSL $PATCH_URL_BASE/varnish-4.1.3_fix_Werror_el6.patch -o varnish-4.1.3_fix_Werror_el6.patch \
	&& echo "$VARNISH_SHA256 *varnish.tar.gz" | sha256sum -c - \
	&& tar -zxf varnish.tar.gz \
	&& cd varnish-$VARNISH_VERSION \
	\
	# Apply Alpine Linux patches so varnish compiles correctly
	&& patch -p1 < /usr/src/fix-compat-execinfo.patch \
	&& patch -p1 < /usr/src/fix-stack-overflow.patch \
	&& patch -p1 < /usr/src/musl-mode_t.patch \
	&& patch < /usr/src/varnish-4.1.3_fix_Werror_el6.patch \
	\
	&& export CFLAGS="-fstack-protector-strong -fpic -fpie -O3 -DTCP_FASTOPEN=23" \
					CPPFLAGS="$CFLAGS" \
					LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie" \
	&& ./configure \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	&& { find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; } \
	&& rm -rf /varnish.tar.gz /varnish-$VARNISH_VERSION \
	&& runDeps="$( \
		scanelf --needed --nobanner --recursive /usr/local \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
	&& apk add --no-cache --virtual .varnish-rundeps $runDeps \
	&& apk del .build-deps \
	&& rm -rf /usr/src \
	\
	# Unset SUID on all files
	&& for i in $(find / -perm /6000 -type f); do chmod a-s $i; done

COPY default.vcl /etc/varnish/default.vcl

USER varnish
WORKDIR /var/lib/varnish

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 8080
CMD ["varnishd"]
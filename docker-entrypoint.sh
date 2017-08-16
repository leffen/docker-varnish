#!/bin/sh
set -e

# If first arg is `something.vcl` test its vcl syntax and return the result
if [ "${1%.vcl}" != "$1" ]; then
	set -- -C -f "/var/lib/varnish/$1"
fi

# If first arg is `-f` or `--some-option` run as a varnishd option
if [ "${1#-}" != "$1" ]; then
	set "$@"
fi

# Run normally if CMD is unmodified
if [ $# = 1 ] && [ "$1" = 'varnishd' ]; then
	# Start logging first if required
	if [ ${VARNISH_DEBUG_LOG_ENABLED:-0} -eq 1 ]; then
		varnishlog \
			-n /var/lib/varnish \
			-q "${VARNISH_DEBUG_LOG_QUERY:-*}" \
			-t 10 $VARNISH_DEBUG_LOG_OPTS &
	elif [ ${VARNISH_LOG_ENABLED:-1} -eq 1 ]; then
		LOG_FORMAT='%h %u %t "%r" %s "%{Referer}i" "%{User-agent}i" %{Varnish:hitmiss}x'
		
		varnishncsa \
			-n /var/lib/varnish \
			-F "${VARNISH_LOG_FORMAT:-$LOG_FORMAT}" \
			-t 10 $VARNISH_LOG_OPTS &
	fi

	# Next start the varnish daemon as PID 1
	exec varnishd \
		-f /etc/varnish/default.vcl \
		-n /var/lib/varnish \
		-s malloc,${VARNISH_MEMORY:-32M} \
		-a "${VARNISH_IP:-0.0.0.0}":${VARNISH_PORT:-8080} \
		-r cc_command,vcc_allow_inline_c,syslog_cli_traffic,vcc_unsafe_path,vmod_dir,vcl_dir \
		-F -p connect_timeout=30 $VARNISH_OPTS
fi

# Fallback for custom user commands
exec "$@"
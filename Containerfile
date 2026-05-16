# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite:stable

# Copy custom systemd user services (e.g. polkit agent, idle management)
COPY services /usr/lib/systemd/user/

# ---------------------------------------------------------------------------
# Build stage: compile Astal runtime libraries + AGS binary from source
# No COPR provides functional Astal or AGS packages for Fedora 44.
# Astal = Vala GObject libraries, AGS = Go binary + JS data.
# All build deps (vala, golang, meson, etc.) stay in this stage;
# only the installed artifacts (/usr/local/) are copied to the final image.
# ---------------------------------------------------------------------------
FROM ghcr.io/ublue-os/bazzite:stable AS ags-builder

RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    dnf5 -y install \
        meson ninja-build git-core \
        vala valadoc \
        gobject-introspection-devel \
        glib2-devel gtk4-devel gtk4-layer-shell-devel \
        golang npm gjs \
        wayland-protocols-devel \
        python3 && \
    # /usr/local -> ../var/usrlocal (dangling symlink in bootc images)
    mkdir -p /var/usrlocal && \
    # Build Astal libraries
    git clone --depth 1 https://github.com/aylur/astal.git /tmp/astal && \
    meson setup /tmp/astal/lib/astal/io/build /tmp/astal/lib/astal/io && \
    meson install -C /tmp/astal/lib/astal/io/build && \
    meson setup /tmp/astal/lib/astal/gtk4/build /tmp/astal/lib/astal/gtk4 && \
    meson install -C /tmp/astal/lib/astal/gtk4/build && \
    meson setup /tmp/astal/lang/gjs/build /tmp/astal/lang/gjs && \
    meson install -C /tmp/astal/lang/gjs/build && \
    # Build AGS
    git clone --depth 1 https://github.com/aylur/ags.git /tmp/ags && \
    cd /tmp/ags && \
    HOME=/tmp GOCACHE=/tmp/go-cache GOPATH=/tmp/go npm install && \
    meson setup build && \
    GOCACHE=/tmp/go-cache GOPATH=/tmp/go meson install -C build

# ---------------------------------------------------------------------------
# Final stage
# ---------------------------------------------------------------------------
FROM ghcr.io/ublue-os/bazzite:stable

# Copy custom systemd user services (e.g. polkit agent, idle management)
COPY services /usr/lib/systemd/user/

# Copy AGS binary + data from the build stage
COPY --from=ags-builder /usr/local/ /usr/local/

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint

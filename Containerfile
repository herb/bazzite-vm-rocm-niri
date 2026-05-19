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
# Installs to /usr/ (not /usr/local/) because in bootc images /usr/local
# is a symlink to /var/usrlocal which is a runtime-only mount.
# ---------------------------------------------------------------------------
FROM ghcr.io/ublue-os/bazzite:stable AS ags-builder

RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    # wireplumber(-libs) is versionlocked in the base bazzite image;
    # lift the lock so we can install wireplumber-devel (which upgrades
    # to the matching Fedora version).
    dnf5 versionlock delete wireplumber-libs wireplumber 2>/dev/null; \
    dnf5 -y install \
        meson ninja-build git-core \
        vala valadoc \
        gobject-introspection-devel \
        glib2-devel gtk4-devel gtk4-layer-shell-devel \
        golang npm gjs \
        wayland-protocols-devel \
        wireplumber-devel \
        NetworkManager-libnm-devel \
        json-glib-devel \
        libgudev-devel \
        python3 && \
    # Build Astal libraries (io -> gtk4 -> gjs)
    git clone --depth 1 https://github.com/aylur/astal.git /tmp/astal && \
    meson setup --prefix /usr /tmp/astal/lib/astal/io/build /tmp/astal/lib/astal/io && \
    meson install -C /tmp/astal/lib/astal/io/build && \
    meson setup --prefix /usr /tmp/astal/lib/astal/gtk4/build /tmp/astal/lib/astal/gtk4 && \
    meson install -C /tmp/astal/lib/astal/gtk4/build && \
    # Build Astal service libraries
    for lib in wireplumber network battery mpris bluetooth apps powerprofiles; do \
        meson setup --prefix /usr /tmp/astal/lib/$lib/build /tmp/astal/lib/$lib && \
        meson install -C /tmp/astal/lib/$lib/build; \
    done && \
    # notifd and brightness default to cli=true which requires quarrel-0.1 (not built)
    for lib in notifd brightness; do \
        meson setup --prefix /usr /tmp/astal/lib/$lib/build /tmp/astal/lib/$lib -Dcli=false && \
        meson install -C /tmp/astal/lib/$lib/build; \
    done && \
    meson setup --prefix /usr /tmp/astal/lang/gjs/build /tmp/astal/lang/gjs && \
    meson install -C /tmp/astal/lang/gjs/build && \
    # Build AGS
    git clone --depth 1 https://github.com/aylur/ags.git /tmp/ags && \
    cd /tmp/ags && \
    HOME=/tmp GOCACHE=/tmp/go-cache GOPATH=/tmp/go npm install && \
    meson setup build --prefix /usr && \
    GOCACHE=/tmp/go-cache GOPATH=/tmp/go meson install -C build

# ---------------------------------------------------------------------------
# Final stage
# ---------------------------------------------------------------------------
FROM ghcr.io/ublue-os/bazzite:stable

# Copy custom systemd user services (e.g. polkit agent, idle management)
COPY services /usr/lib/systemd/user/

# Copy AGS binary + Astal libraries + data from the build stage.
# Build stage uses --prefix /usr so artifacts embed correct paths.
COPY --from=ags-builder /usr/ /usr/

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

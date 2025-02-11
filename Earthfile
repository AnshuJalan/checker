all:
    BUILD +format
    BUILD +build
    BUILD +test
    BUILD +cli
    BUILD +dev-container

# =============================================================================
# Base images
# =============================================================================
# Base image for building project
builder:
    FROM ubuntu:20.04
    ENV DEBIAN_FRONTEND=noninteractive
    RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && sed -i -re 's|disco|focal|g' /etc/apt/sources.list
    RUN apt update && apt install -y \
            autoconf \
            bash \
            curl \
            fd-find \
            gawk \
            git \
            g++ \
            jq \
            libev4 \
            libgmp-dev \
            libhidapi-dev \
            libsodium-dev \
            libsodium23 \
            libtool \
            make \
            m4 \
            net-tools \
            opam \
            openssl \
            pkg-config \
            python-is-python3 \
            python3-pip \
            ruby \
            ruby-json

    # Update language-specific package managers
    RUN pip install --upgrade pip
    ARG POETRY_VERSION="==1.1.8"
    RUN pip install poetry"$POETRY_VERSION"

    RUN mkdir /build
    WORKDIR /build

    # Note: opam prefers that the user has a home directory
    RUN useradd -m checker && chown checker /build
    USER checker

    RUN opam init --disable-sandboxing --bare
    RUN opam update --all

    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:builder

deps-ocaml:
    FROM +builder
    RUN opam switch create . ocaml-base-compiler.4.12.0
    COPY checker.opam ./
    RUN opam install -y --deps-only --with-test --locked=locked ./checker.opam
    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:deps-ocaml

# Note: nesting this below `deps-ocaml` since it is likely to change more often
deps-full:
    FROM +deps-ocaml
    # To improve caching, first install dependencies only
    COPY pyproject.toml .
    COPY poetry.lock .
    RUN poetry config virtualenvs.in-project true && poetry install --no-root
    # Then install the package itself
    COPY ./checker_tools ./checker_tools
    RUN poetry install
    # Image for local use
    SAVE IMAGE checker/deps-full:latest
    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:deps-full

# =============================================================================
# Documentation
# =============================================================================
docs:
    FROM +build-ocaml
    RUN opam exec -- dune build @doc
    SAVE ARTIFACT _build/default/_doc/_html AS LOCAL ./ocaml-docs
    SAVE ARTIFACT _build/default/_doc/_html /ocaml-docs

spec:
    FROM +builder
    RUN pip install sphinx-rtd-theme
    # Add local install path for sphinx since we are running as non-root user
    ENV PATH=/home/checker/.local/bin:$PATH
    COPY docs docs
    RUN make -C docs/spec html
    SAVE ARTIFACT docs/spec/_build/html AS LOCAL docs/spec/_build/html
    SAVE ARTIFACT docs/spec/_build/html /
    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:spec

# =============================================================================
# Comment script (CI only)
# =============================================================================

execute-comment-bot:
    FROM +deps-full

    ARG base_sha = 'UNDEFINED_BASE_SHA'
    ARG head_sha = 'UNDEFINED_HEAD_SHA'

    COPY ./scripts/artifacts.py ./artifacts.py
    RUN poetry run python ./artifacts.py compare-stats --previous "$base_sha" --next "$head_sha"

# =============================================================================
# Formatting
# =============================================================================
format:
    BUILD +format-ocaml
    BUILD +format-python

format-ocaml:
    FROM +deps-ocaml
    COPY ./src ./src
    COPY ./tests ./tests
    COPY ./scripts/format-ocaml.sh .
    RUN opam exec -- ./format-ocaml.sh
    SAVE ARTIFACT src AS LOCAL src
    SAVE ARTIFACT tests AS LOCAL tests

format-python:
    FROM +deps-full
    COPY ./scripts ./scripts
    COPY ./e2e ./e2e
    RUN poetry run ./scripts/format-python.sh
    SAVE ARTIFACT scripts AS LOCAL ./scripts
    SAVE ARTIFACT checker_tools AS LOCAL ./checker_tools
    SAVE ARTIFACT e2e AS LOCAL ./e2e

format-check:
    BUILD +format-ocaml-check
    BUILD +format-python-check

format-ocaml-check:
    FROM +deps-ocaml
    COPY ./src ./src
    COPY ./tests ./tests
    COPY .git .git
    COPY ./scripts/format-ocaml.sh .
    RUN opam exec -- ./format-ocaml.sh && \
        diff="$(git status --porcelain | grep ' M ')" bash -c 'if [ -n "$diff" ]; then echo "Some files require formatting, run \"scripts/format-ocaml.sh\":"; echo "$diff"; exit 1; fi'

format-python-check:
    FROM +deps-full
    COPY .git .git
    COPY ./scripts ./scripts
    COPY ./e2e ./e2e
    RUN poetry run ./scripts/format-python.sh && \
        diff="$(git status --porcelain | grep ' M ')" bash -c 'if [ -n "$diff" ]; then echo "Some files require formatting, run \"scripts/format-python.sh\":"; echo "$diff"; exit 1; fi'

# =============================================================================
# Build & Tests
# =============================================================================
build:
    BUILD +build-ocaml
    BUILD +build-ligo

test:
    BUILD +test-ocaml
    BUILD +test-tools

generate-code:
    FROM +deps-full
    RUN mkdir ./src
    COPY ./scripts/generate-entrypoints.rb ./generate-entrypoints.rb
    COPY ./src/checker.mli ./src/checker.mli
    COPY ./checker.yaml checker.yaml
    # Generate entrypoints
    RUN mkdir generated_src && ./generate-entrypoints.rb ./src/checker.mli > ./generated_src/checkerEntrypoints.ml
    # Generate other src modules using newer code generation tool
    RUN poetry run checker-build generate --out generated_src && cp ./src/_input_checker.yaml ./generated_src
    # Ensure that the generated modules obey formatting rules:
    RUN opam exec -- ocp-indent -i ./generated_src/*.ml*
    SAVE ARTIFACT ./generated_src/*
    SAVE ARTIFACT ./generated_src/* AS LOCAL src/
    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:generate-code

build-ocaml:
    FROM +deps-ocaml
    COPY src/*.ml src/*.mli src/dune ./src/
    COPY +generate-code/* ./src/
    COPY tests/*.ml tests/dune ./tests/
    COPY dune-project ./
    RUN opam exec -- dune build @install
    # Image for inline caching
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:build-ocaml

build-ligo:
    FROM +builder

    COPY +ligo-binary/ligo /bin/ligo
    COPY ./src/*.ml ./src/*.mligo ./src/
    COPY +generate-code/* ./src/
    COPY ./scripts/compile-ligo.rb ./scripts/
    COPY ./scripts/generate-ligo.sh ./scripts/
    COPY ./patches/e2e-tests-hack.patch .

    ARG E2E_TESTS_HACK=""

    # Note: using bash if-then here instead of earthly's IF-END because the earthly
    # version was flaky as of version v0.5.23
    RUN bash -c 'if [ "$E2E_TESTS_HACK" = "true" ]; then patch -p0 <e2e-tests-hack.patch; fi'

    RUN ./scripts/generate-ligo.sh
    RUN ./scripts/compile-ligo.rb

    SAVE ARTIFACT ./generated/ligo /ligo
    SAVE ARTIFACT ./generated/michelson /michelson
    SAVE ARTIFACT ./generated/ligo AS LOCAL ./generated/ligo
    SAVE ARTIFACT ./generated/michelson AS LOCAL ./generated/michelson
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:build-ligo

test-ocaml:
    FROM +build-ocaml
    COPY ./scripts/ensure-unique-errors.sh ./scripts/
    RUN bash ./scripts/ensure-unique-errors.sh
    RUN opam exec -- dune runtest .

test-ocaml-fast:
    FROM +build-ocaml
    COPY ./scripts/ensure-unique-errors.sh ./scripts/
    RUN bash ./scripts/ensure-unique-errors.sh
    RUN opam exec -- dune build @run-fast-tests

test-coverage:
    FROM +build-ocaml
    COPY ./scripts/ensure-unique-errors.sh ./scripts/
    RUN bash ./scripts/ensure-unique-errors.sh
    RUN opam exec -- dune runtest --instrument-with bisect_ppx --force .
    RUN opam exec -- bisect-ppx-report html
    RUN echo "$(opam exec -- bisect-ppx-report summary --per-file)"
    RUN opam exec -- bisect-ppx-report summary --per-file \
      | awk '{ match($0, "^ *([0-9.]+) *% *[^ ]* *(.*)$", res); print res[1] "|" res[2] }' \
      | jq -R "split(\"|\") | { \
          \"value\": .[0] | tonumber, \
          \"key\": (.[1] | if . == \"Project coverage\" then \"TOTAL\" else ltrimstr(\"src/\") end) \
        }" \
      | jq --sort-keys -s 'from_entries' \
      | tee test-coverage.json
    SAVE ARTIFACT _coverage AS LOCAL ./_coverage
    SAVE ARTIFACT test-coverage.json AS LOCAL test-coverage.json
    SAVE ARTIFACT _coverage /_coverage
    SAVE ARTIFACT test-coverage.json

test-tools:
    FROM +deps-full
    RUN poetry run pytest checker_tools

test-e2e:
    FROM +deps-full
    # Bring ligo, which is required for ctez deployment
    COPY +ligo-binary/ligo /bin/ligo
    # Bring ZCash parameters necessary for the node
    COPY +zcash-params/zcash-params /home/checker/.zcash-params
    # Bring ctez contract and mock oracle (for running checker in sandbox)
    COPY ./vendor/ctez ./vendor/ctez
    COPY ./util/mock_oracle.tz ./util/
    COPY ./util/mock_cfmm_oracle.tz ./util/
    # Bring flextesa + tezos-* binaries, which are required by the checker client
    COPY +flextesa/* /usr/bin/
    # And the checker contract itself
    COPY --build-arg E2E_TESTS_HACK=true +build-ligo/michelson ./generated/michelson
    # Also need checker config file
    RUN mkdir ./src
    COPY +generate-code/_input_checker.yaml ./src/_input_checker.yaml
    # Finally, need the e2e tests themselves
    COPY ./e2e ./e2e

    RUN WRITE_GAS_PROFILES=$PWD/gas_profiles.json \
        WRITE_GAS_COSTS=$PWD/gas-costs.json \
        poetry run python ./e2e/main.py

    RUN poetry run python e2e/plot-gas-profiles.py gas_profiles.json --output auction-gas-profiles.png

    SAVE ARTIFACT gas_profiles.json /gas_profiles.json
    SAVE ARTIFACT gas-costs.json /gas-costs.json
    SAVE ARTIFACT auction-gas-profiles.png /auction-gas-profiles.png

test-mutations:
    FROM +build-ocaml

    ARG test_cmd = 'dune build @run-fast-tests'
    ARG n_mutations = "25"
    ARG modules = 'src/burrow.ml src/checker.ml'

    # Need git tree for restoring mutated src files
    COPY .git .git
    COPY scripts/mutate.py ./mutate.py
    RUN opam exec -- ./mutate.py --test "$test_cmd" --num-mutations "$n_mutations" $modules

# =============================================================================
# Other artifacts
# =============================================================================
dev-container:
    FROM +deps-full

    # Extra dependencies for development.
    # Note: not running `apt update` here since package list is updated in prior build stage
    USER root
    RUN apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        wget \
        gosu

    # Install docker
    ARG TARGETARCH
    RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    RUN echo "deb [arch=$TARGETARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && sed -i -re 's|disco|focal|g' /etc/apt/sources.list
    RUN apt update && \
        apt install -y docker-ce docker-ce-cli containerd.io && \
        (getent group docker || groupadd docker) && \
        usermod -aG docker root && \
        usermod -aG docker checker

    # Install earthly.
    # ** Note: earthly will only be usable if the container is launched with access to docker,
    #    e.g. via mounting the host docker socket
    # **
    RUN wget "https://github.com/earthly/earthly/releases/download/v0.5.23/earthly-linux-$TARGETARCH" -O /usr/local/bin/earthly && chmod +x /usr/local/bin/earthly

    # Create default working directory
    RUN mkdir /checker && chown checker /checker

    # Bring in the entrypoint script
    COPY scripts/docker/entrypoint-dev-container.sh ./entrypoint.sh
    RUN chmod +x entrypoint.sh

    # Extra useful applications for development
    COPY +ligo-binary/ligo /bin/ligo
    COPY +zcash-params/zcash-params /home/checker/.zcash-params
    COPY +flextesa/* /usr/bin/

    WORKDIR /checker

    # Ensure that we restore the debian frontend to dialog since the dev container
    # should be interactive.
    ENV DEBIAN_FRONTEND=dialog
    # Set earthly to use caching by default
    ENV EARTHLY_USE_INLINE_CACHE=true

    ENTRYPOINT /build/entrypoint.sh
    ARG TAG = "latest"
    # Local image
    SAVE IMAGE checker/dev:latest
    # Published image
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/dev:$TAG
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/dev:latest

# Note: Building CLI independently so that it doesn't include the full closure of all
# of our dev dependencies
cli:
    FROM ubuntu:20.04

    ENV DEBIAN_FRONTEND=noninteractive
    RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && sed -i -re 's|disco|focal|g' /etc/apt/sources.list
    RUN apt update && apt install -y \
          curl net-tools pkg-config autoconf libtool libev4 \
          libgmp-dev openssl libsodium23 libsodium-dev \
          python3-pip python-is-python3

    RUN pip install --upgrade pip
    ARG POETRY_VERSION="==1.1.8"
    RUN pip install poetry"$POETRY_VERSION"

    RUN useradd -m checker
    USER checker
    WORKDIR /home/checker

    COPY +ligo-binary/ligo /bin/ligo
    COPY +zcash-params/zcash-params /home/checker/.zcash-params
    COPY ./vendor/ctez ./vendor/ctez
    COPY ./util/mock_oracle.tz ./util/
    COPY ./util/mock_cfmm_oracle.tz ./util/

    # Baking in the current version of Checker for convenience
    COPY +build-ligo/michelson ./generated/michelson
    RUN mkdir ./src
    COPY +generate-code/_input_checker.yaml ./src/_input_checker.yaml

    # To improve caching, first install dependencies only
    COPY pyproject.toml .
    COPY poetry.lock .
    RUN poetry config virtualenvs.in-project true && poetry install --no-root
    # Then install the package itself
    COPY ./checker_tools ./checker_tools
    RUN poetry install

    # Required dir for pytezos
    RUN mkdir /home/checker/.tezos-client
    ENV PATH="/home/checker/.venv/bin:$PATH"
    WORKDIR /home/checker
    CMD checker

    ARG TAG=latest
    # Local image
    SAVE IMAGE checker-client:latest
    # Published image
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/checker-client:$TAG
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/checker-client:master

# =============================================================================
# Utilities
# =============================================================================
ligo-binary:
    FROM +ligo
    SAVE ARTIFACT /root/ligo ligo
    SAVE ARTIFACT /root/ligo AS LOCAL ./bin/ligo

ligo:
    # Sadly, the ligo Dockerfile expects that a changelog.txt file exists
    # which does not exist in the git repo. This makes it nearly impossible to
    # integrate with the earthly build here. Running the build scripts ourselves
    # instead...
    # Mostly copy-pasted from https://gitlab.com/ligolang/ligo/-/blob/0.34.0/Dockerfile
    FROM alpine:3.12

    RUN apk update && apk upgrade && apk --no-cache add \
        build-base snappy-dev alpine-sdk wget \
        bash ncurses-dev xz m4 git pkgconfig findutils rsync \
        gmp-dev libev-dev libressl-dev linux-headers pcre-dev perl zlib-dev hidapi-dev \
        libffi-dev \
        cargo

    WORKDIR /ligo

    RUN wget -O /usr/local/bin/opam https://github.com/ocaml/opam/releases/download/2.1.0/opam-2.1.0-x86_64-linux
    RUN chmod u+x /usr/local/bin/opam
    RUN opam init --disable-sandboxing --bare

    ENV RUSTFLAGS='--codegen target-feature=-crt-static'

    # Install opam switch & deps
    COPY /vendor/ligo/scripts/setup_switch.sh /ligo/scripts/setup_switch.sh
    RUN opam update && sh scripts/setup_switch.sh
    COPY /vendor/ligo/scripts/install_opam_deps.sh /ligo/scripts/install_opam_deps.sh
    COPY /vendor/ligo/ligo.opam /ligo
    COPY /vendor/ligo/ligo.opam.locked /ligo
    COPY /vendor/ligo/vendors /ligo/vendors

    # install all transitive deps
    RUN opam update && sh scripts/install_opam_deps.sh
    ENV PATH=/home/root/.cargo/bin:$PATH

    # Install LIGO
    COPY /vendor/ligo/src /ligo/src
    COPY /vendor/ligo/dune /ligo
    COPY /vendor/ligo/dune-project /ligo/dune-project
    # COPY /vendor/ligo/scripts/version.sh /ligo/scripts/version.sh
    RUN LIGO_VERSION=checker opam exec -- dune build -p ligo --profile static

    RUN cp /ligo/_build/install/default/bin/ligo /root/ligo
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:ligo

zcash-params:
    FROM alpine:3.14
    RUN apk add curl wget
    RUN curl https://raw.githubusercontent.com/zcash/zcash/master/zcutil/fetch-params.sh | sh -
    SAVE ARTIFACT /root/.zcash-params /zcash-params
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:zcash-params

flextesa:
    FROM ubuntu:20.04

    ENV DEBIAN_FRONTEND=noninteractive
    RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && sed -i -re 's|disco|focal|g' /etc/apt/sources.list
    RUN apt update && \
        apt install -y \
            curl \
            git \
            bash \
            opam \
            pkg-config \
            cargo \
            autoconf \
            zlib1g-dev \
            libev-dev \
            libffi-dev \
            libusb-dev \
            libhidapi-dev \
            libgmp-dev && \
        rm -rf /var/lib/apt/lists/*

    # Checkout flextesa
    WORKDIR /root
    ARG FLEXTESA_REV = "0d2c0c95e1d745416b191b399b760c98b440e0fd"
    RUN git clone https://gitlab.com/tezos/flextesa.git && cd ./flextesa && git checkout "$FLEXTESA_REV"
    WORKDIR /root/flextesa

    # Create opam switch and install flextesa deps
    ARG OCAML_VERSION = "4.13.1"
    ENV OPAM_SWITCH="flextesa"
    RUN opam init --disable-sandboxing --bare
    RUN opam switch create "$OPAM_SWITCH" "$OCAML_VERSION"
    RUN opam install -y --deps-only \
            ./tezai-base58-digest.opam ./tezai-tz1-crypto.opam \
            ./flextesa.opam ./flextesa-cli.opam

    # Build flextesa
    RUN eval $(opam env) && \
        # Note: setting profile to `dune` to disable deprecation alerts as errors
        export DUNE_PROFILE=dune && \
        make build && \
        mkdir ./bin && \
        cp -L ./flextesa ./bin

    # Fetch the tezos exes which are required by flextesa at runtime
    ARG TARGETARCH
    ARG OCTEZ_VERSION = "11.1.0"
    IF [ "$TARGETARCH" = "amd64" ]
        ARG ARCH_PREFIX = "x86_64"
    ELSE
        ARG ARCH_PREFIX = $TARGETARCH
    END

    RUN echo "Downloading tezos binaries from: https://gitlab.com/api/v4/projects/3836952/packages/generic/tezos/$OCTEZ_VERSION/$ARCH_PREFIX-tezos-binaries.tar.gz"
    RUN curl -s https://gitlab.com/api/v4/projects/3836952/packages/generic/tezos/$OCTEZ_VERSION/$ARCH_PREFIX-tezos-binaries.tar.gz | tar xvz -C . && \
        cp ./tezos-binaries/* ./bin


    SAVE ARTIFACT ./bin/*
    SAVE ARTIFACT ./bin AS LOCAL ./bin
    SAVE IMAGE --push ghcr.io/tezos-checker/checker/earthly-cache:flextesa


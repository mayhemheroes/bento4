FROM ubuntu:22.04

# Setup environment variables
ENV BENTO4_VERSION 1.6.0-639

# Install Dependencies
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates bash python3 make cmake gcc g++ git clang

# Copy Sources
COPY ./ /tmp/bento4

# Build
RUN rm -rf /tmp/bento4/cmakebuild && mkdir -p /tmp/bento4/cmakebuild/x86_64-unknown-linux && cd /tmp/bento4/cmakebuild/x86_64-unknown-linux && cmake -DCMAKE_BUILD_TYPE=Release ../.. && make

# Install
RUN cd /tmp/bento4 && python3 Scripts/SdkPackager.py x86_64-unknown-linux . cmake && mkdir /opt/bento4 && mv /tmp/bento4/SDK/Bento4-SDK-*.x86_64-unknown-linux/* /opt/bento4
RUN clang++ /tmp/bento4/mayhem/fuzz_Find.cpp -fsanitize=fuzzer,address -I /tmp/bento4/Source/C++/Core/ /tmp/bento4/cmakebuild/x86_64-unknown-linux/libap4.a  -o /fuzz

# === Second Stage ===
FROM ubuntu:22.04

# Setup environment variables
ENV PATH=/opt/bento4/bin:${PATH}

# Copy Binaries
COPY --from=0 /opt/bento4 /opt/bento4
COPY --from=0 /fuzz /fuzz_Find

WORKDIR /opt/bento4


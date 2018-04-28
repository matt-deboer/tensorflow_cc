#!/bin/bash
set -e

# configure environmental variables
export CC_OPT_FLAGS=${CC_OPT_FLAGS:-"-march=haswell"}
export TF_NEED_GCP=${TF_NEED_GCP:-0}
export TF_NEED_HDFS=${TF_NEED_HDFS:-0}
export TF_NEED_OPENCL=${TF_NEED_OPENCL:-0}
export TF_NEED_OPENCL_SYCL=${TF_NEED_OPENCL_SYCL:-0}
export TF_NEED_TENSORRT=${TF_NEED_TENSORRT:-0}
export TF_NEED_JEMALLOC=${TF_NEED_JEMALLOC:-1}
export TF_NEED_VERBS=${TF_NEED_VERBS:-0}
export TF_NEED_MKL=${TF_NEED_MKL:-1}
export TF_DOWNLOAD_MKL=${TF_DOWNLOAD_MKL:-1}
export TF_NEED_MPI=${TF_NEED_MPI:-0}
export TF_ENABLE_XLA=${TF_ENABLE_XLA:-1}
export TF_NEED_S3=${TF_NEED_S3:-0}
export TF_NEED_GDR=${TF_NEED_GDR:-0}
export TF_CUDA_CLANG=${TF_CUDA_CLANG:-0}
export TF_SET_ANDROID_WORKSPACE=${TF_SET_ANDROID_WORKSPACE:-0}
export TF_NEED_KAFKA=${TF_NEED_KAFKA:-0}
export PYTHON_BIN_PATH=${PYTHON_BIN_PATH:-"$(which python3)"}
export PYTHON_LIB_PATH="$($PYTHON_BIN_PATH -c 'import site; print(site.getsitepackages()[0])')"

export extra_bazel_config=""
# configure cuda environmental variables

if [ -e /opt/cuda ]; then
	echo "Using CUDA from /opt/cuda"
	export CUDA_TOOLKIT_PATH=/opt/cuda
elif [ -e /usr/local/cuda ]; then
	echo "Using CUDA from /usr/local/cuda"
	export CUDA_TOOLKIT_PATH=/usr/local/cuda
fi

if [ -e /opt/cuda/include/cudnn.h ]; then
	echo "Using CUDNN from /opt/cuda"
	export CUDNN_INSTALL_PATH=/opt/cuda
elif [ -e /usr/local/cuda/include/cudnn.h ]; then
	echo "Using CUDNN from /usr/local/cuda"
	export CUDNN_INSTALL_PATH=/usr/local/cuda
elif [ -e /usr/include/cudnn.h ]; then
	echo "Using CUDNN from /usr"
	export CUDNN_INSTALL_PATH=/usr
fi

if [ -n "${CUDA_TOOLKIT_PATH}" ]; then
    if [[ -z "${CUDNN_INSTALL_PATH}" ]]; then
        echo "CUDA found but no cudnn.h found. Please install cuDNN."
        exit 1
    fi
    echo "CUDA support enabled"
    cuda_config_opts="--config=opt --config=cuda"
    export TF_NEED_CUDA=1
    export TF_CUDA_COMPUTE_CAPABILITIES=${TF_CUDA_COMPUTE_CAPABILITIES:-"3.5,5.2,6.1,6.2"}
    export TF_CUDA_VERSION="$($CUDA_TOOLKIT_PATH/bin/nvcc --version | sed -n 's/^.*release \(.*\),.*/\1/p')"
    export TF_CUDNN_VERSION="$(cat $CUDNN_INSTALL_PATH/include/cudnn.h | grep '#define CUDNN_MAJOR ' | awk '{print $3}')"
    # use gcc-6 for now, clang in the future
	if [ ! -e /usr/bin/gcc-6 ] && [ -e /usr/bin/gcc ] && [ "$(uname -s)" == 'Darwin' ]; then
		# use /usr/bin/gcc (which usually just links to clang) on OSX
		export GCC_HOST_COMPILER_PATH=/usr/bin/gcc
	fi
    export GCC_HOST_COMPILER_PATH=${GCC_HOST_COMPILER_PATH:-"/usr/bin/gcc-6"}
    export CLANG_CUDA_COMPILER_PATH=${CLANG_CUDA_COMPILER_PATH:-"/usr/bin/clang"}
    export TF_CUDA_CLANG=${TF_CUDA_CLANG:-0}
else
	echo "CUDA support disabled"
	cuda_config_opts=""
	export TF_NEED_CUDA=0
fi

if [ "$(uname -s)" == 'Darwin' ]; then
	if [ ! -e /usr/bin/gcc-6 ] && [ -e /usr/bin/gcc ]; then
		# use /usr/bin/gcc (which usually just links to clang) on OSX
		export GCC_HOST_COMPILER_PATH=/usr/bin/gcc
	fi
	# fixes required for compilation w/ CUDA 9+, XCode 8+
	# @see https://github.com/tensorflow/tensorflow/issues/14174
	for file in $(find . -name '*.cu.cc'); do
		sed -i '' -e 's/__align__(sizeof(T))//' $file
	done
	echo "PWD: $(pwd)"
	sed -i '' -e '/-lgomp/d' ./third_party/gpus/cuda/BUILD.tpl

	# @see https://github.com/tensorflow/tensorflow/issues/14127
	# xla_orc_jit="./tensorflow/compiler/xla/service/cpu/simple_orc_jit.cc"
	# mv $xla_orc_jit "${xla_orc_jit}.original"
	# target_line=$(grep -n 'namespace xla {' "${xla_orc_jit}.original" | cut -d ":" -f 1)
	# { 
	# 	head -n $(($target_line-1)) "${xla_orc_jit}.original"; 
	# 	cat <<-EOF
	# 	#if defined(__APPLE__)
	# 	static void sincos(double, double*, double*)  __attribute__((weakref ("__sincos")));
	# 	static void sincosf(float, float*, float*) __attribute__((weakref ("__sincosf")));
	# 	#endif
	# 	EOF
	# 	tail -n +$target_line "${xla_orc_jit}.original"; 
	# } > $xla_orc_jit
	# make bazel respect additional library paths
	extra_bazel_config="--action_env LD_LIBRARY_PATH --action_env DYLD_LIBRARY_PATH"
fi

# fix broken protobuf/eigen includes
# @see https://github.com/tensorflow/tensorflow/issues/17067#issuecomment-366544970
sed -i '' -e 's|"https://mirror.bazel.build/github.com/google/protobuf/archive/396336eb961b75f03b25824fe86cf6490fb75e3a.tar.gz"|"https://mirror.bazel.build/github.com/dtrebbien/protobuf/archive/50f552646ba1de79e07562b41f3999fe036b4fd0.tar.gz"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|"https://github.com/google/protobuf/archive/396336eb961b75f03b25824fe86cf6490fb75e3a.tar.gz"|"https://github.com/dtrebbien/protobuf/archive/50f552646ba1de79e07562b41f3999fe036b4fd0.tar.gz"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|sha256 = "846d907acf472ae233ec0882ef3a2d24edbbe834b80c305e867ac65a1f2c59e3"|sha256 = "eb16b33431b91fe8cee479575cee8de202f3626aaf00d9bf1783c6e62b4ffbc7"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|strip_prefix = "protobuf-396336eb961b75f03b25824fe86cf6490fb75e3a"|strip_prefix = "protobuf-50f552646ba1de79e07562b41f3999fe036b4fd0"|g' ./tensorflow/workspace.bzl

sed -i '' -e 's|"https://mirror.bazel.build/bitbucket.org/eigen/eigen/get/2355b229ea4c.tar.gz"|"https://mirror.bazel.build/bitbucket.org/dtrebbien/eigen/get/374842a18727.tar.gz"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|"https://bitbucket.org/eigen/eigen/get/2355b229ea4c.tar.gz"|"https://bitbucket.org/dtrebbien/eigen/get/374842a18727.tar.gz"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|sha256 = "0cadb31a35b514bf2dfd6b5d38205da94ef326ec6908fc3fd7c269948467214f"|sha256 = "fa26e9b9ff3a2692b092d154685ec88d6cb84d4e1e895006541aff8603f15c16"|g' ./tensorflow/workspace.bzl
sed -i '' -e 's|strip_prefix = "eigen-eigen-2355b229ea4c"|strip_prefix = "dtrebbien-eigen-374842a18727"|g' ./tensorflow/workspace.bzl


# configure and build
./configure
bazel build -c opt \
			$cuda_config_opts \
			--config=monolithic  \
			$extra_bazel_config \
			--copt=${CC_OPT_FLAGS} tensorflow:libtensorflow_cc.so
bazel shutdown

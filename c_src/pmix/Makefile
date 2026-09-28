CC=g++
SWM_C_LIB=../lib
PMIX_INCLUDE?=/usr/lib/x86_64-linux-gnu/pmix2/include
PMIX_LIBDIR?=/usr/lib/x86_64-linux-gnu
# Prefer the multiarch pmix2 lib dir when present (ships the real .so).
PMIX_SO_DIR?=$(shell if [ -f /usr/lib/x86_64-linux-gnu/pmix2/lib/libpmix.so.2 ]; then echo /usr/lib/x86_64-linux-gnu/pmix2/lib; else echo $(PMIX_LIBDIR); fi)
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I${SWM_C_LIB}\
       -I${PMIX_INCLUDE}\
       -Werror\
       -pedantic\
       -g\
       -std=c++17\
       -Wno-deprecated-declarations
# Private lib next to the release bin/ so workers need no system libpmix.
# Use DT_RPATH (not RUNPATH) so it wins over a conflicting ld.so.cache entry.
LDFLAGS=-L${_KERL_ACTIVE_DIR}/usr/lib\
        -L${PMIX_LIBDIR}\
        -L${PMIX_SO_DIR}\
        -Wl,--disable-new-dtags\
        -Wl,-rpath,'$$ORIGIN/../lib'
LIBS=-lpmix\
     -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)
TARGET=swm-pmix
# Copied into the release as lib/libpmix.so.2 (ABI matched to this build).
BUNDLED_LIB=libpmix.so.2

all: $(TARGET) $(BUNDLED_LIB)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $< $(CFLAGS)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBS)

$(BUNDLED_LIB):
	cp -L "$(PMIX_SO_DIR)/libpmix.so.2" "$(BUNDLED_LIB)"

clean:
	rm -f ./*.o $(TARGET) $(BUNDLED_LIB)

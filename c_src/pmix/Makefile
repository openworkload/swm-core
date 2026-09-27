CC=g++
SWM_C_LIB=../lib
PMIX_INCLUDE?=/usr/lib/x86_64-linux-gnu/pmix2/include
PMIX_LIBDIR?=/usr/lib/x86_64-linux-gnu
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I${SWM_C_LIB}\
       -I${PMIX_INCLUDE}\
       -Werror\
       -pedantic\
       -g\
       -std=c++17\
       -Wno-deprecated-declarations
LDFLAGS=-L${_KERL_ACTIVE_DIR}/usr/lib\
        -L${PMIX_LIBDIR}
LIBS=-lpmix\
     -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)
TARGET=swm-pmix

all: $(TARGET)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $< $(CFLAGS)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBS)

clean:
	rm -f ./*.o $(TARGET)

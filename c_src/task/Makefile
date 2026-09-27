CC=g++
SWM_C_LIB=../lib
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I${SWM_C_LIB}\
       -Werror\
       -pedantic\
       -g\
       -std=c++17\
       -Wno-deprecated-declarations
LDFLAGS=-L${_KERL_ACTIVE_DIR}/usr/lib
LIBS=-lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)
TARGET=swm-task

all: $(TARGET)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $< $(CFLAGS)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBS)

clean:
	rm -f ./*.o $(TARGET)

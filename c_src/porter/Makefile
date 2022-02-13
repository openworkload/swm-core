CC=g++
SWM_C_LIB=../lib
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I${SWM_C_LIB}\
       -Werror\
       -pedantic\
       -g\
       -std=c++14\
       -Wno-deprecated-declarations
LDFLAGS=-L${_KERL_ACTIVE_DIR}/usr/lib
LIBS=-lei\
     -lpthread

SRCS=$(shell echo *.cpp)
SRCS_LIB=$(shell echo $(SWM_C_LIB)/*.cpp)
OBJS=$(SRCS:.cpp=.o) $(SRCS_LIB:.cpp=.o)
TARGET=swm-porter

CHECK=cppcheck
CHECK_ARGS=--enable=all\
           --language=cpp\
           --std=cpp14\
           --suppress=missingIncludeSystem\
           -I${SWM_C_LIB}

all: $(TARGET)
	$(MAKE) -C $(SWM_C_LIB)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $< $(CFLAGS)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBS)

clean:
	rm -f ./*.o $(TARGET)

check:
	$(CHECK) $(CHECK_ARGS) .


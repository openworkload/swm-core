CC=g++
SWM_C_LIB=../lib
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I${SWM_C_LIB}\
       -Werror\
       -pedantic\
       -g\
       -std=c++17\
       -Wno-deprecated-declarations\
       -MMD\
       -MP
LDFLAGS=-L${_KERL_ACTIVE_DIR}/usr/lib
LIBS=-lei\
     -lpthread\
     -ldl

SRCS=$(shell echo *.cpp)
SRCS_LIB=$(shell echo $(SWM_C_LIB)/*.cpp)
OBJS=$(SRCS:.cpp=.o) $(SRCS_LIB:.cpp=.o)
DEPS=$(OBJS:.o=.d)
TARGET=swm-porter

CHECK=cppcheck
CHECK_ARGS=--enable=all\
           --language=cpp\
           --std=cpp14\
           --suppress=missingIncludeSystem\
           -I${SWM_C_LIB}

# Build lib objects first so header-driven rebuilds stay consistent.
.PHONY: lib
all: $(TARGET)

lib:
	$(MAKE) -C $(SWM_C_LIB)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $< $(CFLAGS)

$(TARGET): lib $(OBJS)
	$(CC) -o $@ $(OBJS) $(LDFLAGS) $(LIBS)

clean:
	rm -f ./*.o ./*.d $(TARGET)

-include $(DEPS)

check:
	$(CHECK) $(CHECK_ARGS) .


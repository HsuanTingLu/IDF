# Make IDF_HOME available to the sim at run time
export IDF_HOME := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
TRICK_GTE_EXT += IDF_HOME

# Header, SimObject, and Python module paths
EXTERNALS         := externals/idf
THIRD_PARTY       := $(IDF_HOME)/3rdParty/trick
INCLUDE           := $(IDF_HOME)/include
TRICK_CFLAGS      += -I$(INCLUDE)
TRICK_CXXFLAGS    += -I$(INCLUDE)
TRICK_SFLAGS      += -I$(THIRD_PARTY)/sim_objects
TRICK_PYTHON_PATH += :$(EXTERNALS)/3rdParty/trick/python:$(THIRD_PARTY)/python

# Links to be built by build_externals
LINKS := $(EXTERNALS)/apps/vhc/build $(EXTERNALS)/3rdParty/trick/python

# Libraries
ifeq ($(TRICK_HOST_TYPE), Linux)
    TRICK_LDFLAGS += -ludev -lrt
else ifeq ($(TRICK_HOST_TYPE), Darwin)
    TRICK_LDFLAGS += -framework IOKit -framework CoreFoundation
endif

# Enable library support if Trick >= 17.1
ifneq ($(wildcard $(TRICK_HOME)/share/trick/makefiles/trickify.mk),)

    # Additional links to be built by build_externals
    LINKS += $(EXTERNALS)/3rdParty/trick/lib/python

    # Tell SWIG where to find *.i files
    SWIG_FLAGS += -I$(THIRD_PARTY)/lib

    # Tell Trick to expect io_* and py_* code for these headers, but not to generate it itself.
    # This is different than ICG_EXCLUDE, which would cause Trick to ignore the io_* and py_* code.
    TRICK_EXT_LIB_DIRS += :$(INCLUDE)

    # Tell Trick where to find the Python modules generated by SWIG
    TRICK_PYTHON_PATH += :$(EXTERNALS)/3rdParty/trick/lib/python:$(THIRD_PARTY)/lib/python

    # Link in the Trickified object and core library
    TRICK_LDFLAGS += $(THIRD_PARTY)/lib/trickified_idf.o $(IDF_HOME)/build/lib/libidf.a

    # Append prerequisites to the $(S_MAIN) target, causing the libraries to be built along with the sim
    $(S_MAIN): libidf $(THIRD_PARTY)/lib/trickified_idf.o

    # Ultimately, we need the Trickified object to link against. So if it doesn't
    # exist, we need to build it. However, we also need to rebuild it if any of
    # its dependencies change. S_source.d automatically maintains these
    # dependencies in a rule for which S_source.d itself is the target. For our
    # purposes, the Trickified object depends on S_source.d.
    # We avoid using variables in the recipe because:
    # - Their resolution is deferred until the recipe runs.
    # - This file is meant to be included by the user's S_overrides.mk.
    # - If a variable (such as THIRD_PARTY) is set any time after this file is
    #   included, it will have that value when this recipe runs.
    $(THIRD_PARTY)/lib/trickified_idf.o: $(THIRD_PARTY)/lib/build/S_source.d
	    $(MAKE) -s -C $(dir $@)

    # Because S_source.d specifies the target as itself rather than the Trickified
    # library (the reason for this is explained in trickify.mk), we need to declare
    # a rule for S_source.d and flesh out its dependencies by including S_source.d
    # (which is done at the bottom).
    # We use a target-specific variable with simple expansion to ensure the
    # desired value is used in the recipe. The use of override prevents
    # command-line overriding.
    $(THIRD_PARTY)/lib/build/S_source.d: override DIR := $(THIRD_PARTY)/lib
    $(THIRD_PARTY)/lib/build/S_source.d:
	    @$(MAKE) -s -C $(DIR)

    -include $(THIRD_PARTY)/lib/build/S_source.d
else
    # Trick will be building all of IDF, so we need to add the path for use with LIBRARY_DEPENDENCY
    SOURCE := $(IDF_HOME)/source
    TRICK_CFLAGS   += -I$(SOURCE)
    TRICK_CXXFLAGS += -I$(SOURCE)
endif

# Include libntcan, if available
ifdef NTCAN_HOME
    TRICK_CFLAGS   += -I$(NTCAN_HOME) -DIDF_CAN
    TRICK_CXXFLAGS += -I$(NTCAN_HOME) -DIDF_CAN
    TRICK_LDFLAGS  += -L$(NTCAN_HOME) -lntcan
endif

libidf:
	@$(MAKE) -s -C $(IDF_HOME)

build_externals: $(LINKS)

$(dir $(LINKS)):
	@mkdir -p $@

clean: clean_idf

clean_idf:
	@rm -rf externals/idf

.SECONDEXPANSION:

$(LINKS): $(EXTERNALS)% : $(IDF_HOME)% | $$(dir $$@)
	@ln -s $< $@

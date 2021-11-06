from setuptools import setup, find_packages

with open("README.md", "r") as fh:
    long_description = fh.read()

setup(
     name='swmclient',
     version='0.0.1',
     description='Sky Workload Manager core daemon python interface',
     long_description=long_description,
     long_description_content_type="text/markdown",
     keywords='hpc highperformancecomputing workload cloud computing jupyter',
     url='https://github.com/skyworkflows/swm-core/python',
     author='Taras Shapovalov',
     author_email='taras@iclouds.net',
     packages=['swmclient'],
     include_package_data=True,
     classifiers=[
         "Programming Language :: Python :: 3",
         "License :: OSI Approved :: BSD License",
         "Operating System :: OS Independent",
     ],
     install_requires=[]
)

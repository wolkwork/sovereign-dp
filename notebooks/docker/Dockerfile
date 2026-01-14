FROM quay.io/jupyter/minimal-notebook:latest

# Install only essential packages for lakehouse queries
RUN pip install --no-cache-dir \
    trino \
    pandas \
    ipython-sql \
    'prettytable<3.10'

# Set Trino connection defaults
ENV TRINO_HOST="trino.pileus.svc.cluster.local"
ENV TRINO_PORT="8080"
ENV TRINO_CATALOG="iceberg"

# Copy demo notebook to a location that won't be overwritten by PVC mount
USER root
RUN mkdir -p /opt/notebooks
COPY trino-iceberg-demo.ipynb /opt/notebooks/
RUN chown -R jovyan:users /opt/notebooks/
USER jovyan

WORKDIR /home/jovyan

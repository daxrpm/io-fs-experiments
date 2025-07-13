#!/bin/bash

# Este script limpia las caches del kernel de Linux (page cache, dentries, e inodes).
# Es crucial para asegurar que cada prueba de E/S se ejecute en condiciones
# similares, sin la influencia del cache de pruebas anteriores.
#
# Referencia: La gestión de la memoria caché es un concepto clave discutido en
# Stallings, Cap. 11, en el contexto de rendimiento de E/S. Al limpiar
# la caché, forzamos al sistema a leer desde el disco, midiendo el
# rendimiento real del dispositivo y del mecanismo de E/S, no la velocidad de la RAM.
#
# ¡ADVERTENCIA! Este script debe ejecutarse con privilegios de superusuario (root)
# y puede afectar temporalmente el rendimiento del sistema.

# Comprobar si el usuario es root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ser ejecutado como root o con sudo." 1>&2
   exit 1
fi

echo "Sincronizando datos en disco..."
# sync() asegura que todos los datos en buffers se escriban en disco.
sync

echo "Limpiando PageCache, dentries e inodes..."
# Escribir '3' en drop_caches limpia todo lo posible.
# 1: Limpia PageCache.
# 2: Limpia dentries e inodes.
# 3: Limpia PageCache, dentries e inodes.
echo 3 > /proc/sys/vm/drop_caches

# El README recomienda usar 'tee' para que el script de ejecución
# pueda llamarlo con 'sudo' sin necesidad de una shell interactiva.
# Ejemplo: sudo tee /proc/sys/vm/drop_caches <<< "3"

echo "Caches limpiadas exitosamente." 
# Manual para Experimentos TCP/IP entre 2 PCs (Arch Linux)

Este manual explica cómo ejecutar las pruebas de TCP/IP entre dos máquinas separadas en Arch Linux para obtener resultados reales de comunicación en red.

## 🖥️ Configuración de los PCs

### PC 1 (Servidor)
- **IP:** 192.168.1.100 (ejemplo - usar la IP real)
- **Puerto:** 12345
- **Función:** Recibe archivos y los guarda

### PC 2 (Cliente)  
- **IP:** 192.168.1.101 (ejemplo - usar la IP real)
- **Función:** Lee archivos locales y los envía al servidor

## 📋 Pasos de Preparación

### 1. Preparar Ambos PCs

En **ambos** PCs, ejecuta:

```bash
# Instalar dependencias (Arch Linux)
sudo pacman -Syu
sudo pacman -S base-devel python python-pip

# Instalar librerías de Python
pip install pandas matplotlib seaborn

# Clonar/copiar el proyecto
cd ~/Desktop/EPN/SO/Linux-IO-FS/lab2-io-fs-experiments

# Compilar programas
make

# Generar archivos de prueba
bash test_data/generate_files.sh

# Crear directorio de prueba (en ambos PCs)
sudo mkdir -p /mnt/ext4test
sudo chown $(whoami):$(whoami) /mnt/ext4test
```

### 2. Configurar Permisos de Sudo

En **ambos** PCs, edita el archivo sudoers:

```bash
sudo EDITOR=nano visudo
```

Añade esta línea (reemplaza `tu_usuario`):
```
tu_usuario ALL=(ALL) NOPASSWD: /usr/bin/tee /proc/sys/vm/drop_caches
```

### 3. Verificar Conectividad

En PC2, prueba la conectividad:
```bash
ping 192.168.1.100  # IP del PC1
```

## 🚀 Ejecución del Experimento

### Paso 1: Iniciar el Servidor (PC1)

En **PC1**, ejecuta:

```bash
cd ~/Desktop/EPN/SO/Linux-IO-FS/lab2-io-fs-experiments
chmod +x scripts/run_all_network.sh
./scripts/run_all_network.sh server
```

El servidor comenzará a esperar conexiones en el puerto 12345.

### Paso 2: Ejecutar el Cliente (PC2)

En **PC2**, ejecuta:

```bash
cd ~/Desktop/EPN/SO/Linux-IO-FS/lab2-io-fs-experiments
chmod +x scripts/run_all_network.sh
./scripts/run_all_network.sh client 192.168.1.100  # IP del PC1
```

## 📊 Análisis de Resultados

### Opción 1: Análisis Local (en cada PC)

En cada PC, ejecuta:
```bash
python scripts/stats_parser_network.py
```

### Opción 2: Análisis Combinado

1. **Copia los resultados** de PC2 a PC1:
```bash
# En PC2
scp -r results/raw/tcp_socket/ usuario@192.168.1.100:~/Desktop/EPN/SO/Linux-IO-FS/lab2-io-fs-experiments/results/raw/
```

2. **Analiza en PC1**:
```bash
# En PC1
python scripts/stats_parser_network.py
```

## 📈 Resultados Esperados

El experimento generará:

- **`results/summary_network.csv`**: Estadísticas detalladas
- **`results/charts/tcp_client_vs_server.png`**: Comparación cliente vs servidor
- **`results/charts/tcp_syscalls_by_side.png`**: Análisis de llamadas al sistema
- **`results/charts/tcp_cpu_time_by_side.png`**: Análisis de tiempo de CPU

## 🔧 Solución de Problemas (Arch Linux)

### Error de Conexión
```bash
# Verificar que el puerto esté abierto en PC1
ss -tuln | grep 12345

# Verificar firewall (si usas iptables)
sudo iptables -L

# O si usas ufw (instalar primero)
sudo pacman -S ufw
sudo ufw status
sudo ufw allow 12345
```

### Error de Permisos
```bash
# Verificar permisos del directorio
ls -la /mnt/ext4test

# Si es necesario, cambiar propietario
sudo chown -R $(whoami):$(whoami) /mnt/ext4test
```

### Error de Compilación
```bash
# Instalar herramientas de desarrollo (Arch Linux)
sudo pacman -S base-devel

# Limpiar y recompilar
make clean
make
```

### Error con Python/pip
```bash
# Si hay problemas con pip, usar pacman para pandas
sudo pacman -S python-pandas python-matplotlib python-seaborn

# O actualizar pip
python -m pip install --upgrade pip
```

### Error con strace
```bash
# En Arch Linux, strace viene con base-devel
# Si no está disponible:
sudo pacman -S strace
```

## 📝 Notas Específicas para Arch Linux

1. **Gestor de Paquetes**: Usa `pacman` en lugar de `apt-get`
2. **Python**: En Arch, `python` es Python 3 por defecto
3. **Herramientas de Desarrollo**: `base-devel` incluye gcc, make, etc.
4. **Firewall**: Arch no tiene firewall por defecto, pero puedes instalar `ufw` o `iptables`
5. **Sincronización**: El servidor debe estar ejecutándose antes de que el cliente intente conectarse.

## 🎯 Interpretación de Resultados

- **Cliente**: Mide el tiempo de lectura del archivo + envío por red
- **Servidor**: Mide el tiempo de recepción + escritura del archivo
- **Diferencia**: La diferencia entre cliente y servidor incluye la latencia de red

Los resultados te permitirán comparar:
- Rendimiento de red vs. E/S local
- Overhead de TCP/IP vs. sockets UNIX
- Impacto del tamaño de buffer en rendimiento de red

## 🔍 Comandos Útiles de Arch Linux

```bash
# Verificar paquetes instalados
pacman -Q | grep python

# Verificar servicios de red
systemctl status NetworkManager

# Verificar conectividad de red
ip addr show
ip route show

# Verificar puertos abiertos
ss -tuln

# Verificar uso de memoria y CPU
htop
```

## ⚠️ Consideraciones Especiales para Arch

1. **Rolling Release**: Arch se actualiza constantemente, asegúrate de tener el sistema actualizado
2. **Minimalismo**: Arch viene con pocos paquetes por defecto, instala lo que necesites
3. **Configuración Manual**: Arch requiere más configuración manual que otras distribuciones
4. **AUR**: Si necesitas paquetes adicionales, considera usar el AUR con `yay` o `paru` 
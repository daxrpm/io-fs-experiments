# Manual para Experimentos TCP/IP entre 2 PCs

Este manual explica cómo ejecutar las pruebas de TCP/IP entre dos máquinas separadas para obtener resultados reales de comunicación en red.

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
# Instalar dependencias
sudo apt-get update
sudo apt-get install -y build-essential python3 python3-pip
pip3 install pandas matplotlib seaborn

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
sudo visudo
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
python3 scripts/stats_parser_network.py
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
python3 scripts/stats_parser_network.py
```

## 📈 Resultados Esperados

El experimento generará:

- **`results/summary_network.csv`**: Estadísticas detalladas
- **`results/charts/tcp_client_vs_server.png`**: Comparación cliente vs servidor
- **`results/charts/tcp_syscalls_by_side.png`**: Análisis de llamadas al sistema
- **`results/charts/tcp_cpu_time_by_side.png`**: Análisis de tiempo de CPU

## 🔧 Solución de Problemas

### Error de Conexión
```bash
# Verificar que el puerto esté abierto en PC1
netstat -tuln | grep 12345

# Verificar firewall
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
# Instalar herramientas de desarrollo
sudo apt-get install -y build-essential

# Limpiar y recompilar
make clean
make
```

## 📝 Notas Importantes

1. **Sincronización**: El servidor debe estar ejecutándose antes de que el cliente intente conectarse.

2. **Red**: Asegúrate de que ambos PCs estén en la misma red y puedan comunicarse.

3. **Tiempo**: El experimento completo puede tardar varias horas.

4. **Recursos**: El experimento usa mucha CPU y disco. Cierra otras aplicaciones.

5. **Logs**: Los logs se guardan en `results/raw/tcp_socket/` con separación cliente/servidor.

## 🎯 Interpretación de Resultados

- **Cliente**: Mide el tiempo de lectura del archivo + envío por red
- **Servidor**: Mide el tiempo de recepción + escritura del archivo
- **Diferencia**: La diferencia entre cliente y servidor incluye la latencia de red

Los resultados te permitirán comparar:
- Rendimiento de red vs. E/S local
- Overhead de TCP/IP vs. sockets UNIX
- Impacto del tamaño de buffer en rendimiento de red 
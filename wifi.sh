#!/bin/bash

connect_wifi() {
    ssid=$1
    password=$2
    interface=$3
    
    echo "Escaneando red $ssid..."
    
    
    scan_result=$(sudo iw dev $interface scan | sed -n "/SSID: $ssid/,/BSS/p")
    if echo "$scan_result" | grep -E "RSN|WPA|Privacy" > /dev/null; then
        echo "La red usa seguridad (WPA/WPA2/WPA3)."
        
        
        config_file="/tmp/wpa_supplicant-$interface.conf"
        wpa_passphrase "$ssid" "$password" | sudo tee "$config_file" > /dev/null
        
        
        sudo killall -q wpa_supplicant
        sleep 1
        
        
        echo "Conectando a red segura $ssid..."
        sudo wpa_supplicant -B -i "$interface" -c "$config_file"
        sleep 3
        
        if iw dev $interface link | grep -q "Connected to"; then
            echo "Conexión WiFi establecida correctamente."
           
            sudo rm -f "$config_file"
        else
            echo "Error al conectar. Verifica SSID y contraseña."
            sudo rm -f "$config_file"
            return 1
        fi
    else
        echo "La red parece ser abierta, conectando..."
        sudo iw dev "$interface" connect "$ssid"
        
        
        sleep 3
        if iw dev $interface link | grep -q "Connected to"; then
            echo "Conexión a red abierta establecida correctamente."
        else
            echo "Error al conectar a red abierta."
            return 1
        fi
    fi
    
    return 0
}


configure_ip() {
    interface=$1
    echo "¿Quieres configuración dinámica (DHCP) o estática? (D/E)"
    read config_type
    
    if [ "$config_type" == "D" ] || [ "$config_type" == "d" ]; then
        echo "Usando DHCP..."
        sudo dhclient -r "$interface"  
        if sudo dhclient "$interface"; then
            echo "Configuración DHCP aplicada correctamente."
        else
            echo "Error al aplicar configuración DHCP."
            return 1
        fi
    else
        echo "Introduce la IP estática (ejemplo: 192.168.1.100):"
        read ip
        
        
        if ! echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "Formato de IP inválido."
            return 1
        fi
        
        echo "Introduce la máscara de subred (ejemplo: 24 para /24):"
        read netmask
        
        
        if ! echo "$netmask" | grep -qE '^[0-9]{1,2}$' || [ "$netmask" -lt 1 ] || [ "$netmask" -gt 32 ]; then
            echo "Máscara de subred inválida. Debe ser un número entre 1 y 32."
            return 1
        fi
        
        echo "Introduce la puerta de enlace (ejemplo: 192.168.1.1):"
        read gateway
        
        
        if ! echo "$gateway" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "Formato de puerta de enlace inválido."
            return 1
        fi
        
        echo "Introduce el servidor DNS primario (ejemplo: 8.8.8.8):"
        read dns
        
        
        if ! echo "$dns" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "Formato de servidor DNS inválido."
            return 1
        fi
        
        
        sudo ip addr flush dev "$interface"
        
        
        if sudo ip addr add "$ip/$netmask" dev "$interface" &&
           sudo ip route add default via "$gateway" dev "$interface" &&
           echo "nameserver $dns" | sudo tee /etc/resolv.conf > /dev/null; then
            echo "Configuración IP estática aplicada correctamente."
        else
            echo "Error al aplicar configuración IP estática."
            return 1
        fi
    fi
    
    return 0
}


if [ "$(id -u)" -ne 0 ]; then
    echo "Este script necesita privilegios de superusuario."
    echo "Por favor, ejecútalo con sudo."
    exit 1
fi


echo "====================================="
echo "  Script de Configuración de Red"
echo "====================================="


echo "¿Quieres usar una conexión cableada o inalámbrica? (C/I)"
read connection_type

if [ "$connection_type" == "C" ] || [ "$connection_type" == "c" ]; then
    echo "Interfaces cableadas disponibles:"
    ip link show | grep "^[0-9]" | awk '{print $2}' | grep -E "^e|^en|^eth" | sed 's/://'
elif [ "$connection_type" == "I" ] || [ "$connection_type" == "i" ]; then
    echo "Interfaces inalámbricas disponibles:"
    ip link show | grep "^[0-9]" | awk '{print $2}' | grep -E "^w|^wl" | sed 's/://'
else
    echo "Opción no válida. Saliendo."
    exit 1
fi

echo "Escribe el nombre de la interfaz:"
read interface


if ! ip link show "$interface" &> /dev/null; then
    echo "La interfaz $interface no existe. Saliendo."
    exit 1
fi

down=$(ip link show "$interface" | grep -i "DOWN" | wc -l)
if [ "$down" -gt 0 ]; then
    echo "La interfaz está abajo, subiéndola..."
    if sudo ip link set "$interface" up; then
        echo "Interfaz activada correctamente."
        sleep 2
    else
        echo "Error al activar la interfaz."
        exit 1
    fi
else
    echo "La interfaz está arriba."
fi


if [ "$connection_type" == "C" ] || [ "$connection_type" == "c" ]; then
    echo "Configurando red cableada en $interface..."
    configure_ip "$interface"
else
    echo "Escaneando redes inalámbricas disponibles..."
    sudo iw dev "$interface" scan | grep -E "SSID:" | sed 's/^[[:space:]]*SSID: //' | sort | uniq
    
    echo "Escribe el SSID de la red a la que deseas conectarte:"
    read ssid
    
    echo "Escribe la contraseña (déjala vacía si es red abierta):"
    read -s password  
    echo ""
    
    if connect_wifi "$ssid" "$password" "$interface"; then
        echo "Configurando direccionamiento IP..."
        configure_ip "$interface"
    else
        echo "No se pudo establecer la conexión WiFi."
        exit 1
    fi
fi


echo "Verificando conectividad..."
if ping -c 3 8.8.8.8 &> /dev/null; then
    echo "Conectividad a Internet confirmada."
else
    echo "Advertencia: No hay conectividad a Internet."
fi

echo "====================================="
echo "Información de la conexión actual:"
echo "====================================="
ip addr show "$interface"
echo "-------------------------------------"
ip route | grep default
echo "-------------------------------------"
cat /etc/resolv.conf | grep nameserver
echo "====================================="

echo "Configuración de red completada."

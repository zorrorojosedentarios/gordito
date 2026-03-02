# Gordito Addon (WoW 3.3.5a)

**Gordito** es un addon avanzado para World of Warcraft (WotLK 3.3.5a) diseñado para la gestión eficiente de festines en bandas y grupos. Su objetivo principal es evitar el desperdicio de comidas, detectar jugadores "glotones" que hacen clic de más y rastrear con precisión quién falta por recibir el beneficio de comida.

## 🚀 Características Principales

- **Doble Columna Inteligente**: Una interfaz limpia que separa la configuración (izquierda) de la gestión de jugadores (derecha).
- **Detección de Glotones**: Registra y avisa si alguien hace clic repetidamente en el festín o come más de lo necesario.
- **Rastreo de "Bien Alimentado"**: Identifica con precisión quién no tiene el beneficio de 1 hora. Solo quita a los jugadores de la lista de faltantes cuando realmente tienen el bufo final.
- **Aviso Dual**: Capacidad de enviar avisos por Chat (Banda/Grupo) y Alerta de Banda (RW) de forma simultánea.
- **Auto-Reset**: Se reinicia automáticamente cuando alguien coloca un nuevo festín.
- **Botón Rastrear**: Permite actualizar la lista de faltantes manualmente sin cerrar la ventana.
- **Icono en Minimapa**: Acceso rápido y visual del estado del addon (Verde = Activo, Gris = Inactivo).

## 🛠️ Comandos de Chat

Puedes usar `/gordito` seguido de:
- `(vacio)`: Abre o cierra el panel principal.
- `toggle`: Activa o desactiva la protección contra clics accidentales.
- `avisos`: Activa o desactiva los anuncios automáticos en el grupo.
- `debug`: Activa el modo depuración para ver eventos detallados en el chat.
- `panel`: Abre explícitamente el panel de configuración.

## ⚙️ Configuración

Dentro del panel podrás ajustar:
- **Umbrales de Clics**: Cuántos clics disparan un aviso y cuántos una alerta de banda.
- **Tiempos de Gracia**: Tiempo de espera al colocar el festín y entre anuncios.
- **Mensajes Personalizados**: Edita los textos que el addon enviará al grupo (admite `%n` para el nombre y `%c` para la cuenta).

## 📄 Notas Técnicas
- Compatible con **Festín de Pescado**, **Gran Festín** y **Festín Abundante**.
---
**Desarrollado por:** zorrorojo (Sedentarios)


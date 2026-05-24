# Gordito Addon (WoW 3.3.5a)

**Gordito** es un addon avanzado para World of Warcraft (WotLK 3.3.5a) diseñado para la gestión eficiente de festines en bandas y grupos. Su objetivo principal es evitar el desperdicio de comidas, detectar jugadores "glotones" que hacen clic de más y rastrear con precisión quién falta por recibir el beneficio de comida.

## 🚀 Características Principales

- **Doble Columna Inteligente**: Una interfaz limpia que separa la configuración (izquierda) de la gestión de jugadores (derecha).
- **Detección de Glotones**: Registra y avisa si alguien hace clic repetidamente en el festín o come más de lo necesario.
- **Rastreo de "Bien Alimentado"**: Identifica con precisión quién no tiene el beneficio de 1 hora. Solo quita a los jugadores de la lista de faltantes cuando realmente tienen el bufo final.
- **Aviso Inteligente de Canal**: Evita la duplicación innecesaria de mensajes. Si una alerta es enviada por Alerta de Banda (RW), se omite inteligentemente del chat normal para mantener el chat limpio.
- **Auto-Reset**: Se reinicia automáticamente cuando alguien coloca un nuevo festín.
- **Botón Rastrear**: Permite actualizar la lista de faltantes manualmente sin cerrar la ventana.
- **Icono en Minimapa**: Acceso rápido y visual del estado del addon (Verde = Activo, Gris = Inactivo).

## 🆕 Novedades y Mejoras Recientes (v2.3)

- **Optimización Antimensajes Duplicados**: Cuando los modos de aviso `ALERTA` y `CHAT` están activos simultáneamente, el addon prioriza inteligentemente el canal `RAID_WARNING` y bloquea la duplicación en `RAID` chat.
- **Alertas Locales Silenciosas**: Los avisos de *"está poniendo un festín..."* y *"canceló la colocación del festín"* ahora son **locales** (solo tú los ves en pantalla y consola). Esto evita el spam masivo y confuso en el chat grupal mientras el festín aún se está casteando.
- **Corrección de Falso Positivo al Comer**: Se parchó el error crítico del ID de hechizo `57397` (Festín de pescado). Anteriormente, cuando cualquier miembro de la banda hacía clic para comer, el addon lo detectaba erróneamente como la colocación de un nuevo festín y mandaba el aviso falso. Ahora, comer se registra correctamente sin reiniciar la cola de anuncios.

## 🛠️ Comandos de Chat

Puedes usar `/gordito` seguido de:
- `(vacio)`: Abre o cierra el panel principal.
- `toggle`: Activa o desactiva la protección contra clics accidentales.
- `debug`: Activa/desactiva logs detallados de eventos en la consola local.
- `ver`: Consulta y solicita la versión instalada por los demás miembros del grupo que usan Gordito.

## ⚙️ Configuración

Dentro del panel podrás ajustar:
- **Umbrales de Clics**: Cuántos clics disparan un aviso y cuántos una alerta de banda.
- **Tiempos de Gracia**: Tiempo de espera al colocar el festín y entre anuncios.
- **Mensajes Personalizados**: Edita los textos que el addon enviará al grupo (admite `%n` para el nombre y `%c` para la cuenta).

## 📄 Notas Técnicas
- Compatible con **Festín de Pescado**, **Gran Festín** y **Festín Abundante**.

---
**Desarrollado por:** Zorrorojo/Miabuelita (Guild Sedentarios)

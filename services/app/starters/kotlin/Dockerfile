FROM gradle:8-jdk21 AS builder
WORKDIR /app
COPY . .
RUN gradle build --no-daemon 2>/dev/null || echo "Configure your build system"

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
USER nobody
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]

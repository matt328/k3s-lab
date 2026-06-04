package dev.teeter.demos.orders;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.openfeign.EnableFeignClients;

@SpringBootApplication
@EnableFeignClients(basePackages = "dev.teeter.demos.payments.api")
public class OrdersServiceApplication {
  public static void main(String[] args) {
    SpringApplication.run(OrdersServiceApplication.class, args);
  }
}

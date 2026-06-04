package dev.teeter.demos.orders.api;

import org.springframework.stereotype.Service;

import dev.teeter.demos.orders.model.Order;

@Service
public class MyOrdersApiDelegate implements OrdersApiDelegate {

  @Override
  public Order ordersIdGet(String id) {
    Order order = new Order();
    order.setId(id);
    order.status(Order.StatusEnum.PENDING);
    return order;
  }

}

package dev.teeter.demos.orders.api;

import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import dev.teeter.demos.orders.model.Order;

@Service
public class MyOrdersApiDelegate implements OrdersApiDelegate {
  private static final Logger log = LoggerFactory.getLogger(MyOrdersApiDelegate.class);

  @Override
  public Order ordersIdGet(String id) {
    log.info("Returning order {}", id);

    Order order = new Order();
    order.setId(id);
    order.status(Order.StatusEnum.PENDING);
    return order;
  }

}

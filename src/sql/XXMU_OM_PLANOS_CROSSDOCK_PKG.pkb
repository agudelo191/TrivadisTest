create or replace package body XXMU_OM_PLANOS_CROSSDOCK_PKG is

/************************************************************************************
 PACKAGE:         XXMU_OM_PLANOS_CROSSDOCK_PKG
 CREADO POR:      Alexander GOMEZ.
 FECHA CREACION:  31/ENE/2016 1:24:32 PM
 DESCRIPCION:     Generacion de Plano para pedidos -Entregas  Cross Docking

 TUNNING:
 FECHA ACTUALIZACION:

************************************************************************************/



/************************************************************************************
 Procedure:        pr_fnd_file
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento para imprimir en el log del registro
 FECHA ACTUALIZACION:
************************************************************************************/
  PROCEDURE pr_fnd_file(pv_msg IN VARCHAR2) IS
  BEGIN
    fnd_file.put_line(fnd_file.log, pv_msg);
  END pr_fnd_file;


/************************************************************************************
 Procedure:        pr_main
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento principal que genera un plano con la información de pedido y
                   Entregas  Cross Docking
 FECHA ACTUALIZACION: 10-FEB-2017
                   Se eliminan  parametros tipo de pedido y pedido
                   Se adicionan  los paraemtros pv_trx_number y pn_cust_account_id

************************************************************************************/

 procedure pr_main (errbuf                 out varchar2,
                    retcode                out varchar2,
                    pn_org_id              in number,
                    pn_cust_account_id     in number,
                    pv_trx_number          in varchar2,
                    pv_separador            in varchar2,
                    pn_decimales            in number,
                    pv_ruta                 in varchar2,
                    pv_extension            in varchar2
                    ) is


  cursor cr_entregas(pn_customer_trx_id in number) is
   SELECT
    rownum line,
    fv_ean_emp_provedor(pn_org_id) ean_emp_prov,
    cust_acct.cust_account_id,
    --cust_acct.account_number,
    (select party.jgzz_fiscal_code
       from hz_parties party
      where party.party_id = cust_acct.party_id) account_number,
    fv_ean_cliente_desp(cust_acct.account_number) ean_cliente,
    (select party.party_name
       from hz_parties party
      where party.party_id = cust_acct.party_id) cliente,
    ultimate_dropoff_location_id,    --  cust_acsi.ece_tp_location_code,
    to_CHAR(wdd.date_requested, 'YYYYMMDDHH24MI') request_date,
    null total_caja_factura,
    oha.cust_po_number oc,
    null fecha_oc,
    mb.segment1 articulo,
    mb.description descripcion_art,
    wdd.item_description,
    fv_cross_reference(wdd.inventory_item_id, 'CGP_CO_EAN13' ) ean_articulo,
    wdd.requested_quantity,
    wdd.shipped_quantity,
    null tipo_embarque,
    fv_edi_location (cust_acct.cust_account_id,wdd.deliver_to_location_id,'DELIVER_TO') ean_dir_entrega,
    wdd.net_weight,
    wdd.volume,
    trx.trx_number,
   /* fv_trx_number(wdd.org_id,
                  wdd.source_header_number,
                  wdd.source_line_id,
                  wnd.name
                  ) trx_number,*/
    wnd.delivery_id


     from wsh_delivery_Details     wdd,
          wsh_new_deliveries       wnd,
          wsh_delivery_assignments wda,
          oe_order_lines_all       ool,
          oe_order_headers_all     oha,
          hz_cust_accounts_all     cust_acct,
          mtl_system_items_b       mb,
          ( select
             ctx.org_id,
             ctx.customer_trx_id,
             ctx.trx_number,
             dtx.sales_order,
             ctx.bill_to_customer_id,
             dtx.interface_line_attribute1  pedido,
           --  dtx.interface_line_attribute2 tipo_pedido,
             to_number(dtx.interface_line_attribute3)  entrega,
             to_number(dtx.interface_line_attribute6)  line_id_ped,
           --  dtx.warehouse_id,
             to_number(ctx.interface_header_attribute10) org_entrga
            from ra_customer_trx_all ctx
                 ,ra_customer_trx_lines_all dtx
            where 1=1
            and dtx.customer_trx_id=ctx.customer_trx_id
            and dtx.line_type='LINE'
          ) trx

    WHERE 1 = 1
     -- and wdd.source_header_id = pn_header_id --24960680
      and wdd.released_status = 'C'
      and wda.delivery_detail_id = wdd.delivery_detail_id --44883176
      AND wda.delivery_id = wnd.delivery_id
      AND wdd.source_header_id = ool.header_id
      AND wdd.source_line_id = ool.line_id
      and wdd.oe_interfaced_flag = 'Y'
      and wdd.inventory_item_id = mb.inventory_item_id
      and wdd.organization_id = mb.organization_id
      and ool.header_id = oha.header_id
      and ool.sold_to_org_id = cust_acct.cust_account_id
      and wdd.source_header_number=trx.pedido
     -- and trx.trx_number=pv_trx_number
      and trx.customer_trx_id=pn_customer_trx_id
      and trx.org_id=pn_org_id
      and trx.bill_to_customer_id=pn_cust_account_id
      and wnd.delivery_id=trx.entrega
    --  and wdd.org_id=pn_org_id

      and NVL(ool.cancelled_flag, 'N') <> 'Y'
      and wdd.org_id = pn_org_id;

vv_cadena_cab           varchar2(4000);
vv_cadena_line          varchar2(4000);

vv_nit_prov              hz_cust_accounts_all.account_number%type;
vv_nombre_prov           hz_parties.party_name%type;
vv_edi_location          hz_cust_acct_sites_all.ece_tp_location_code%type;
vc_line                  constant varchar(1):='_';


ftArchivoSalida          UTL_FILE.FILE_TYPE;
vv_NombreArchivo         varchar2(150);
vrc_registro             tyrec_RegDeliver;
vv_result                varchar2(1);
vn_error                 number:=0;
vv_ruta                  all_directories.directory_path%type;
vv_order_number          oe_order_headers_all.order_number%type;
vn_customer_trx_id       ra_customer_trx_all.customer_trx_id%type;

  begin


vv_ruta:=fv_ruta_directorio(pv_ruta);


pr_fnd_file('Pametros: ');
pr_fnd_file('pn_org_id: '||pn_org_id);
pr_fnd_file('pv_trx_number: '||pv_trx_number);
pr_fnd_file('pn_decimales: '||pn_decimales);
pr_fnd_file('pv_ruta: '||pv_ruta||' '||vv_ruta);
pr_fnd_file('pv_extencion: '||pv_extension||' '||vv_ruta);

if vv_ruta is not null then

          pr_info_emp_provedor(pn_org_id,
                               vv_nit_prov,
                               vv_nombre_prov
                               );

          vn_customer_trx_id:=fv_trx_number(pn_org_id ,pv_trx_number,pn_cust_account_id);

        <<ENTREGAS>>
        for rc_entregas in cr_entregas(vn_customer_trx_id) loop

            --Cabecera del plano
            if rc_entregas.line=1 then
               fnd_file.put_line(fnd_file.OUTPUT,'Cabecera');
               pr_fnd_file('Cabecera');
               fnd_file.put_line(fnd_file.OUTPUT,'Pedido: '||vv_order_number||' ,'||'Entrega: '||rc_entregas.delivery_id);

               vv_NombreArchivo:=rc_entregas.ean_cliente||vc_line||rc_entregas.oc||vc_line||to_CHAR(sysdate, 'YYYYMMDD');
               vv_edi_location:= fv_edi_location (rc_entregas.cust_account_id,rc_entregas.ultimate_dropoff_location_id,'SHIP_TO');

               vrc_registro.vv_ean_emp_prov:=rc_entregas.ean_emp_prov;
               vrc_registro.vv_nit_prov:=vv_nit_prov;
               vrc_registro.vv_nombre_prov:=vv_nombre_prov;
               vrc_registro.vv_ean_cliente:=rc_entregas.ean_cliente;
               vrc_registro.vv_cliente:=rc_entregas.cliente;
               vrc_registro.vv_edi_location:=vv_edi_location;
               vrc_registro.vv_request_date:=rc_entregas.request_date;
               vrc_registro.vn_total_caja_factura:=round(rc_entregas.total_caja_factura,pn_decimales);

               pr_valida_cabecera(vrc_registro,vv_result);
               vv_cadena_cab:=  vrc_registro.vv_ean_emp_prov||pv_separador||
                                vrc_registro.vv_nit_prov||pv_separador||
                                vrc_registro.vv_nombre_prov||pv_separador||
                                vrc_registro.vv_ean_cliente||pv_separador||
                                vrc_registro.vv_cliente||pv_separador||
                                vrc_registro.vv_edi_location||pv_separador||
                                vrc_registro.vv_request_date||pv_separador||
                                vrc_registro.vn_total_caja_factura;

                 pr_fnd_file(vv_cadena_cab);

                  if vv_result='Y' then
                        ftArchivoSalida := UTL_FILE.FOPEN(pv_ruta, vv_NombreArchivo ||'.'||pv_extension,'W',32767);
                        UTL_FILE.put_line(ftArchivoSalida,vv_cadena_cab);
                   else
                        vn_error:= -1;
                  end if;


                fnd_file.put_line(fnd_file.OUTPUT,'Lineas');
                pr_fnd_file('Lineas');
             end if;


    --        lineas del pedido
                fnd_file.put_line(fnd_file.OUTPUT,'Entrega: '||rc_entregas.delivery_id||' ,Articulo '||rc_entregas.articulo);

                vrc_registro.vv_oc:=rc_entregas.oc;
                vrc_registro.vv_fecha_oc:=rc_entregas.fecha_oc;
                vrc_registro.vv_articulo:=rc_entregas.articulo;
                vrc_registro.vv_descripcion_art:=rc_entregas.descripcion_art;
                vrc_registro.vv_ean_articulo:=rc_entregas.ean_articulo;
                vrc_registro.vn_requested_quantity:=round(rc_entregas.requested_quantity,pn_decimales);
                vrc_registro.vn_Shipped_Quantity:=round(rc_entregas.Shipped_Quantity,pn_decimales) ;
                vrc_registro.vn_tipo_embarque:=round(rc_entregas.tipo_embarque,pn_decimales);
                vrc_registro.vv_ean_dir_entrega:=rc_entregas.ean_dir_entrega;
                vrc_registro.vv_trx_number:=pv_trx_number;
                vrc_registro.vn_net_weight:=round(rc_entregas.net_weight,pn_decimales);
                vrc_registro.vn_volume:=round(rc_entregas.volume,pn_decimales);

                --Valida campos obligatorios para registro de lineas
                pr_valida_lineas(vrc_registro,vv_result);

                vv_cadena_line:=vrc_registro.vv_oc||pv_separador||
                                 vrc_registro.vv_fecha_oc||pv_separador||
                                 vrc_registro.vv_articulo||pv_separador||
                                 vrc_registro.vv_descripcion_art||pv_separador||
                                 vrc_registro.vv_ean_articulo||pv_separador||
                                 vrc_registro.vn_requested_quantity||pv_separador||
                                 vrc_registro.vn_Shipped_Quantity||pv_separador||
                                 vrc_registro.vn_tipo_embarque||pv_separador||
                                 vrc_registro.vv_ean_dir_entrega||pv_separador||
                                 vrc_registro.vv_trx_number||pv_separador||
                                 vrc_registro.vn_net_weight||pv_separador||
                                 vrc_registro.vn_volume||pv_separador;

               pr_fnd_file(vv_cadena_line);

                if  vv_result='Y' then
                    UTL_FILE.put_line(ftArchivoSalida,vv_cadena_line);
                 else
                      vn_error:=-1;
                 end if;

        end loop ENTREGAS;

        if vn_error=0 then
            utl_file.fclose(ftArchivoSalida);
             fnd_file.put_line(fnd_file.OUTPUT,'Se genero el archivo '||vv_NombreArchivo);
        else
           --remover el archivo
           utl_file.fremove(pv_ruta,vv_NombreArchivo ||'.'||pv_extension );
        end if;
 end if;

exception
  when others then
   ERRBUF := '[ERROR]: pr_main: ' || RETCODE || ' ' ||
                         substr(SQLERRM, 1, 800) || ' - Trace: '||
                         DBMS_UTILITY.format_error_backtrace;

   pr_fnd_file('[ERROR]: pr_main: ' || RETCODE || ' ' ||
                     substr(SQLERRM, 1, 800) || ' - Trace: '||
                     DBMS_UTILITY.format_error_backtrace);
   RETCODE := 2;

 end pr_main;

/************************************************************************************
 Procedure:        pr_valida_cabecera
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento para validar campos obligatorios a nivel de registro de
                   cabecera
 FECHA ACTUALIZACION:
************************************************************************************/

procedure pr_valida_cabecera(prc_deliver    in tyrec_RegDeliver,
                                 pv_result      out varchar2
                                 ) is

    vv_result                  varchar2(1):='Y';
    vv_mensaje                 fnd_new_messages.message_text%type;
    vc_error                   constant varchar2(20):='ERROR: ';

    begin

        if prc_deliver.vv_ean_emp_prov is null then
            fnd_message.clear;
            fnd_message.set_name ('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_1');
            vv_mensaje := fnd_message.get;
            fnd_file.put_line(fnd_file.OUTPUT, vc_error||' '||vv_mensaje);
            vv_result:='N';
        end if;

        if prc_deliver.vv_nit_prov  is null then
            fnd_message.clear;
            fnd_message.set_name ('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_2');
            vv_mensaje := fnd_message.get;
            fnd_file.put_line(fnd_file.OUTPUT, vc_error||' '||vv_mensaje);
            vv_result:='N';
        end if;

        if prc_deliver.vv_ean_cliente  is null then
            fnd_message.clear;
            fnd_message.set_name ('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_3');
            vv_mensaje := fnd_message.get;
            fnd_file.put_line(fnd_file.OUTPUT, vc_error||' '||vv_mensaje);
            vv_result:='N';
        end if;

        if prc_deliver.vv_edi_location  is null then
            fnd_message.clear;
            fnd_message.set_name ('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_4');
            vv_mensaje := fnd_message.get;
            fnd_file.put_line(fnd_file.OUTPUT, vc_error||' '||vv_mensaje);
            vv_result:='N';
        end if;

         if prc_deliver.vv_request_date is null then
            fnd_message.clear;
            fnd_message.set_name ('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_5');
            vv_mensaje := fnd_message.get;
            fnd_file.put_line(fnd_file.OUTPUT, vc_error||' '||vv_mensaje);
            vv_result:='N';
         end if;

        pv_result:=vv_result;


exception
  when others then
   pr_fnd_file('[ERROR]: pr_valida_cabecera: ' ||substr(SQLERRM, 1, 800) || ' - Trace: '||DBMS_UTILITY.format_error_backtrace);

end pr_valida_cabecera;

/************************************************************************************
 Procedure:        pr_valida_lineas
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento para validar campos obligatorios a nivel de registro de
                   lineas
 FECHA ACTUALIZACION:
************************************************************************************/


procedure pr_valida_lineas(prc_deliver in tyrec_RegDeliver,
                           pv_result   out varchar2) is

  vv_result  varchar2(1) := 'Y';
  vv_mensaje fnd_new_messages.message_text%type;
  vc_error constant varchar2(20) := 'ERROR: ';
begin

  if prc_deliver.vv_oc is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_12');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vv_ean_articulo is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_6');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vn_Shipped_Quantity is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_7');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vv_ean_dir_entrega is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_8');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vv_trx_number is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_9');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vn_net_weight is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_10');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  if prc_deliver.vn_volume is null then
    fnd_message.clear;
    fnd_message.set_name('XBOL', 'XXMU_OM_MENSAJE_CROSSDOCK_11');
    vv_mensaje := fnd_message.get;
    fnd_file.put_line(fnd_file.OUTPUT, vc_error || ' ' || vv_mensaje);
    vv_result := 'N';
  end if;

  pv_result := vv_result;

exception
  when others then
    pr_fnd_file('[ERROR]: pr_valida_lineas: ' || substr(SQLERRM, 1, 800) ||
                ' - Trace: ' || DBMS_UTILITY.format_error_backtrace);

end pr_valida_lineas;

/************************************************************************************
 Procedure:        fv_directorio
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion para validar la ruta del  directorio
 FECHA ACTUALIZACION:
************************************************************************************/
function fv_ruta_directorio(pv_directorio in varchar2) return varchar2 is

  vv_ruta all_directories.directory_path%type;

begin

  <<DIRECTORIO>>
  BEGIN
    select directory_path
      into vv_ruta
      from all_directories
     where directory_name = pv_directorio;

  EXCEPTION
    WHEN OTHERS THEN
      vv_ruta := null;
       pr_fnd_file('No se enconro directorio en all_directories');
  END DIRECTORIO;

  return vv_ruta;

end fv_ruta_directorio;


/************************************************************************************
 Procedure:        fv_pedido
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion que retorna el numero de pedido a partir del ID
 FECHA ACTUALIZACION:
************************************************************************************/
function fv_pedido(pn_header_id in number) return number is

  vv_order_number oe_order_headers_all.order_number%type;

begin

  <<PEDIDO>>
  BEGIN
    SELECT order_number
      into vv_order_number
      FROM oe_order_headers_all oha
     WHERE oha.header_id = pn_header_id;

  EXCEPTION
    WHEN OTHERS THEN
      vv_order_number := null;
  END PEDIDO;

  return vv_order_number;

end fv_pedido;


 /************************************************************************************
 Procedure:        fv_ean_emp_provedor
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento que a partir de la unidad operativa, devuelve el EAN
 FECHA ACTUALIZACION:
************************************************************************************/


function fv_ean_emp_provedor(pn_org_id in number) return varchar2 is

  cursor cr_ean_prov is
    select flv.lookup_code ean
      from fnd_lookup_values_vl flv
     where flv.LOOKUP_TYPE = 'XXMU_EAN_UNIDAD_OPERATIVA'
       and flv.ATTRIBUTE2 = to_char(pn_org_id)
       and flv.ENABLED_FLAG='Y'
       AND SYSDATE BETWEEN flv.START_DATE_ACTIVE AND
           nvl(flv.END_DATE_ACTIVE, SYSDATE)
       and rownum = 1;

  vv_ean varchar2(150);
begin

  open cr_ean_prov;
  fetch cr_ean_prov
    into vv_ean;

  if cr_ean_prov%notfound then
    vv_ean := null;
  end if;
  close cr_ean_prov;

  return vv_ean;

EXCEPTION
  WHEN OTHERS THEN
    pr_fnd_file('[ERROR]: fv_ean_emp_provedor: ' ||
                substr(SQLERRM, 1, 800) || ' - Trace: ' ||
                DBMS_UTILITY.format_error_backtrace);

end fv_ean_emp_provedor;

/************************************************************************************
 Procedure:        pr_info_emp_provedor
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Procedimiento contiene informacion de la empresa proveedora
 FECHA ACTUALIZACION:
************************************************************************************/

procedure pr_info_emp_provedor(pn_org_id in number,
                               pv_nit    out varchar2,
                               pv_nombre out varchar2) is

  cursor cr_info_emp is
     select x.party_id, 
            hp.jgzz_fiscal_code account_number,
            --cust_acct.account_number, 
            x.name 
            
      from xle_entity_profiles  x,
           hr_operating_units   pr,
           hz_cust_accounts_all cust_acct,
           hz_parties hp
     where x.legal_entity_id = pr.default_legal_context_id
       and pr.organization_id = pn_org_id
       and cust_acct.party_id = x.party_id
       and cust_acct.party_id=hp.party_id;

  rc_info_emp cr_info_emp%rowtype;

begin

  open cr_info_emp;
  fetch cr_info_emp
    into rc_info_emp;

    if cr_info_emp%notfound then
      rc_info_emp := null;
    end if;

  close cr_info_emp;
  pv_nit    := rc_info_emp.account_number;
  pv_nombre := rc_info_emp.name;

EXCEPTION
  WHEN OTHERS THEN
    pr_fnd_file('[ERROR]: pr_info_emp_provedor: ' ||
                substr(SQLERRM, 1, 800) || ' - Trace: ' ||
                DBMS_UTILITY.format_error_backtrace);

end pr_info_emp_provedor;

/************************************************************************************
 Procedure:        fv_ean_cliente_desp
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion que retorna Codigo de EAN del cliente de despacho
 FECHA ACTUALIZACION:
************************************************************************************/

 function fv_ean_cliente_desp(pv_nit in varchar2) return varchar2 is

  vv_ean varchar2(150);
 begin

  <<EAN>>

      begin
          select  flv.lookup_code
           into vv_ean
           from fnd_lookup_values_vl flv
          where flv.LOOKUP_TYPE='XXMU_EAN_CLIENTES'
          and  flv.enabled_flag='Y'
          and flv.description=pv_nit
          AND    SYSDATE BETWEEN flv.START_DATE_ACTIVE AND nvl(flv.END_DATE_ACTIVE, SYSDATE);
      exception
        when others then
          vv_ean:=null;
      end EAN;

 return vv_ean;

end fv_ean_cliente_desp;

/************************************************************************************
 Procedure:        fv_edi_location
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion que retorna Codigo de EAN a partir de la direccion de entrega
 FECHA ACTUALIZACION:
************************************************************************************/

function fv_edi_location (Pn_cust_account_id in number,
                          pn_location_id in number,
                          pv_site_use_code in varchar2
                          ) return varchar2 is

cursor cr_edi_location  is
select  ece_tp_location_code
        from hz_cust_accounts_all    cust_acct,
               hz_cust_acct_sites_all cust_acsi,
               hz_cust_site_uses_all  cust_al,
               hz_parties             party,
               hz_party_sites         hps
         where party.party_id = cust_acct.party_id
           and cust_acsi.cust_account_id = cust_acct.cust_account_id
           and  cust_acsi.cust_acct_site_id= cust_al.cust_acct_site_id
           AND cust_acsi.party_site_id= hps.party_site_id(+)
           and  cust_acct.cust_account_id=Pn_cust_account_id
         --  AND  cust_al.Location=49361
           and cust_al.site_use_code= pv_site_use_code --'SHIP_TO'
            And cust_acct.status = 'A'
            and cust_al.status='A'
            and cust_acsi.Status='A'
            and  hps.location_id=pn_location_id;

vv_edi_location     hz_cust_acct_sites_all.ece_tp_location_code%type;


begin

    open cr_edi_location;
    fetch cr_edi_location
    into vv_edi_location;

    if cr_edi_location%notfound then
       vv_edi_location:=null;
    end if;
    close cr_edi_location;

    return vv_edi_location;

   EXCEPTION
    WHEN OTHERS THEN
      pr_fnd_file('[ERROR]: fv_edi_location: ' ||substr(SQLERRM, 1, 800) || ' - Trace: '||DBMS_UTILITY.format_error_backtrace);

end fv_edi_location;

/************************************************************************************
 Procedure:        fv_cross_reference
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion que retorna la referencia cruzada de un articulo
 FECHA ACTUALIZACION:
************************************************************************************/

function fv_cross_reference(pn_inventory_item_id in number,
                            pv_cross_reference_type in varchar2
                           ) return varchar2 is

cursor cr_cross_reference is
  select  cr.cross_reference
   from MTL_CROSS_REFERENCES_B cr
  where cr.cross_reference_type=pv_cross_reference_type --'CGP_CO_EAN13'
   and inventory_item_id=pn_inventory_item_id;

vv_ean_articulo    mtl_cross_references_b.cross_reference%type;
begin

 open cr_cross_reference;
 fetch cr_cross_reference
 into vv_ean_articulo;

     if cr_cross_reference%notfound then
         vv_ean_articulo:=null;
     end if;

 close cr_cross_reference;

 return vv_ean_articulo;

EXCEPTION
    WHEN OTHERS THEN
      pr_fnd_file('[ERROR]: fv_cross_reference: ' ||substr(SQLERRM, 1, 800) || ' - Trace: '||DBMS_UTILITY.format_error_backtrace);

end fv_cross_reference;

/************************************************************************************
 Procedure:        fv_trx_number
 CREADO POR:       Alexander GOMEZ. - Ceiba Software
 DESCRIPCION:      Funcion que retorna el id de la factura
 FECHA ACTUALIZACION:
************************************************************************************/
function fv_trx_number(pn_org_id          in number,
                       pv_trx_number      in varchar2,
                       pn_cust_account_id in number
                       ) return number is

vv_trx_id  ra_customer_trx_all.customer_trx_id%type;

begin

 <<FACTURA>>
begin

   select ctx.customer_trx_id
     into vv_trx_id
    from ra_customer_trx_all ctx
    where ctx.trx_number=pv_trx_number
    and ctx.org_id=pn_org_id
    and ctx.bill_to_customer_id=pn_cust_account_id;

 EXCEPTION
    WHEN OTHERS THEN
      vv_trx_id:=null;
      pr_fnd_file('[ERROR]: fv_trx_number: '||'Numero de factura Invalida' ||substr(SQLERRM, 1, 800) || ' - Trace: '||DBMS_UTILITY.format_error_backtrace);

END FACTURA;

  return vv_trx_id;

end fv_trx_number;


end XXMU_OM_PLANOS_CROSSDOCK_PKG;
/
